<?php

namespace App\Http\Controllers;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Stripe\Exception\SignatureVerificationException;
use Stripe\Webhook;

class StripeCommandeController extends CommandeController
{
    private function client()
    {
        $secret = (string) config('services.stripe.secret');
        abort_unless(str_starts_with($secret, 'sk_test_'), 503,
            'Stripe n’est pas configuré. Ajoutez une clé sk_test_ dans boutique-api/.env.');
        return Http::withToken($secret)->acceptJson()->timeout(25)
            ->withHeaders(['Stripe-Version' => '2026-10-28.endive']);
    }

    public function checkout(Request $request)
    {
        $client = $this->client();
        $data = $this->donnees($request, false);
        $empreinte = hash('sha256', json_encode(Arr::except($data, 'cle_idempotence')));
        $commande = DB::table('commandes')->where('cle_idempotence', $data['cle_idempotence'])->first();
        if (! $commande) {
            [$lignes, $total] = $this->catalogue($data);
            DB::table('commandes')->insertOrIgnore([
                'reference' => (string) Str::uuid(), 'cle_idempotence' => $data['cle_idempotence'],
                'empreinte' => $empreinte, 'statut' => 'en_attente', 'total_centimes' => $total,
                'lignes' => json_encode($lignes), 'livraison' => json_encode($data['livraison']),
                'created_at' => now(), 'updated_at' => now(),
            ]);
            $commande = DB::table('commandes')->where('cle_idempotence', $data['cle_idempotence'])->first();
        }
        abort_unless(hash_equals($commande->empreinte, $empreinte), 409,
            'Cette tentative correspond à un autre panier.');
        abort_if(in_array($commande->statut, ['paye_test', 'expire']), 409,
            'Cette session est terminée. Créez une nouvelle tentative.');
        if (! $commande->stripe_session_id) {
            $retour = rtrim(config('services.stripe.return_url'), '/');
            abort_unless(filter_var($retour, FILTER_VALIDATE_URL) &&
                in_array(parse_url($retour, PHP_URL_SCHEME), ['https', 'http']) &&
                ! parse_url($retour, PHP_URL_QUERY) && ! parse_url($retour, PHP_URL_FRAGMENT),
                503, 'STRIPE_RETURN_URL doit être une URL sans paramètres ni fragment.');
            $params = [
                'mode' => 'payment', 'payment_method_types' => ['card'], 'locale' => 'fr',
                'success_url' => $retour.'/?stripe_session={CHECKOUT_SESSION_ID}',
                'cancel_url' => $retour.'/?stripe_cancelled=1',
                'client_reference_id' => $commande->reference,
                'metadata' => ['commande_reference' => $commande->reference],
                'line_items' => array_map(fn ($ligne) => [
                    'quantity' => $ligne['quantite'],
                    'price_data' => [
                        'currency' => 'eur', 'unit_amount' => $ligne['prix_unitaire_centimes'],
                        'product_data' => ['name' => $ligne['titre']],
                    ],
                ], json_decode($commande->lignes, true)),
            ];
            try {
                $response = $client->asForm()->withHeaders([
                    'Idempotency-Key' => 'checkout-'.$commande->cle_idempotence,
                ])->post('https://api.stripe.com/v1/checkout/sessions', $params);
            } catch (ConnectionException $exception) {
                abort(503, 'Stripe est temporairement inaccessible. Réessayez la même tentative.');
            }
            abort_unless($response->successful(), 502,
                'Impossible de créer la session Stripe. Vérifiez la clé de test et réessayez.');
            $session = $response->json();
            abort_unless(($session['livemode'] ?? null) === false &&
                str_starts_with($session['id'] ?? '', 'cs_test_') &&
                parse_url($session['url'] ?? '', PHP_URL_HOST) === 'checkout.stripe.com' &&
                parse_url($session['url'] ?? '', PHP_URL_SCHEME) === 'https', 502, 'Session Stripe de test invalide.');
            DB::table('commandes')->where('id', $commande->id)->update([
                'stripe_session_id' => $session['id'], 'stripe_url' => $session['url'], 'updated_at' => now(),
            ]);
            $commande = DB::table('commandes')->find($commande->id);
        }
        return response()->json([
            'mode' => 'stripe_test', 'session_id' => $commande->stripe_session_id,
            'checkout_url' => $commande->stripe_url, 'reference' => $commande->reference,
            'total_centimes' => $commande->total_centimes,
        ]);
    }

    public function statut(string $sessionId)
    {
        abort_unless(str_starts_with($sessionId, 'cs_test_') && strlen($sessionId) < 255, 404);
        $commande = DB::table('commandes')->where('stripe_session_id', $sessionId)->first();
        abort_unless($commande, 404);
        // Une URL de retour ou un paramètre client ne constitue jamais une preuve de paiement.
        try {
            $response = $this->client()->get('https://api.stripe.com/v1/checkout/sessions/'.rawurlencode($sessionId));
        } catch (ConnectionException $exception) {
            abort(503, 'Vérification Stripe indisponible. Réessayez.');
        }
        abort_unless($response->successful(), 502, 'Impossible de vérifier le paiement auprès de Stripe.');
        $commande = $this->confirmer($response->json());
        return response()->json([
            'mode' => 'stripe_test', 'reference' => $commande->reference,
            'statut' => $commande->statut, 'total_centimes' => $commande->total_centimes,
            'lignes' => json_decode($commande->lignes, true), 'devise' => 'EUR',
        ]);
    }

    public function webhook(Request $request)
    {
        $secret = (string) config('services.stripe.webhook_secret');
        abort_unless(str_starts_with($secret, 'whsec_'), 503, 'Webhook Stripe non configuré.');
        try {
            $event = Webhook::constructEvent($request->getContent(), $request->header('Stripe-Signature', ''), $secret);
        } catch (SignatureVerificationException|\UnexpectedValueException $exception) {
            abort(400, 'Signature Stripe invalide.');
        }
        abort_unless($event->livemode === false, 400, 'Seuls les événements Stripe de test sont acceptés.');
        if (in_array($event->type, ['checkout.session.completed', 'checkout.session.expired',
            'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed'])) {
            $session = $event->data->object->toArray();
            if (DB::table('commandes')->where('stripe_session_id', $session['id'] ?? '')->exists()) {
                $this->confirmer($session);
            }
        }
        return response()->json(['received' => true]);
    }

    private function confirmer(array $session): object
    {
        $commande = DB::table('commandes')->where('stripe_session_id', $session['id'] ?? '')->first();
        abort_unless($commande && ($session['livemode'] ?? null) === false &&
            ($session['mode'] ?? null) === 'payment' &&
            ($session['client_reference_id'] ?? null) === $commande->reference &&
            ($session['metadata']['commande_reference'] ?? null) === $commande->reference &&
            ($session['currency'] ?? null) === 'eur' &&
            ($session['amount_total'] ?? null) === $commande->total_centimes,
            409, 'La session Stripe ne correspond pas à la commande.');
        $statut = ($session['payment_status'] ?? '') === 'paid' && ($session['status'] ?? '') === 'complete'
            ? 'paye_test' : (($session['status'] ?? '') === 'expired' ? 'expire' : 'en_attente');
        DB::table('commandes')->where('id', $commande->id)->where('statut', '!=', 'paye_test')
            ->update(['statut' => $statut, 'updated_at' => now()]);
        return DB::table('commandes')->find($commande->id);
    }
}
