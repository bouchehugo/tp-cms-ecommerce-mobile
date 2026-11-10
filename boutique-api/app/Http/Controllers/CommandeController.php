<?php

namespace App\Http\Controllers;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CommandeController extends Controller
{
    public function payer(Request $request)
    {
        // Ce simulateur ne dispose d'aucun accès à un prestataire bancaire.
        abort_unless(config('services.paiement_demo'), 403, 'Le paiement de démonstration est désactivé.');
        foreach (array_keys(Arr::dot($request->all())) as $champ) {
            if (preg_match('/(^|\.)(card_number|numero_carte|cvv|cvc|expiration|date_expiration)$/i', $champ)) {
                throw ValidationException::withMessages(['paiement' => 'Aucune donnée de carte bancaire ne doit être envoyée.']);
            }
        }
        $data = $request->validate([
            'cle_idempotence' => 'required|uuid',
            'scenario' => 'required|in:accepte,refuse',
            'total_attendu_centimes' => 'required|integer|min:1',
            'lignes' => 'required|array|min:1|max:50',
            'lignes.*.document_id' => 'required|string|max:100|distinct',
            'lignes.*.quantite' => 'required|integer|min:1|max:999',
            'livraison' => 'required|array',
            'livraison.prenom' => 'required|string|max:100',
            'livraison.nom' => 'required|string|max:100',
            'livraison.adresse' => 'required|string|max:255',
            'livraison.complement' => 'nullable|string|max:255',
            'livraison.code_postal' => 'required|string|max:20',
            'livraison.ville' => 'required|string|max:100',
            'livraison.telephone' => 'required|string|max:30',
            'livraison.email' => 'required|email|max:255',
        ]);
        $empreinte = hash('sha256', json_encode(Arr::except($data, 'cle_idempotence')));
        $existante = DB::table('commandes_demo')->where('cle_idempotence', $data['cle_idempotence'])->first();
        if ($existante) {
            abort_unless(hash_equals($existante->empreinte, $empreinte), 409, 'Cette tentative correspond à un autre panier.');
            return $this->resultat($existante);
        }

        $lignes = [];
        $total = 0;
        foreach ($data['lignes'] as $ligne) {
            try {
                $reponse = Http::acceptJson()->timeout(10)->get(
                    rtrim(config('services.strapi.url'), '/').'/api/articles/'.rawurlencode($ligne['document_id'])
                );
            } catch (ConnectionException $exception) {
                abort(503, 'Le catalogue est indisponible. Réessayez dans un instant.');
            }
            abort_if($reponse->serverError(), 503, 'Le catalogue est indisponible.');
            $article = $reponse->json('data');
            if (! $reponse->successful() || ! is_array($article) || ($article['documentId'] ?? null) !== $ligne['document_id']) {
                throw ValidationException::withMessages(['lignes' => 'Un article n’est plus disponible. Actualisez le catalogue.']);
            }
            $prix = $article['prix'] ?? null;
            $stock = $article['stock'] ?? null;
            if (! is_numeric($prix) || $prix <= 0 || $prix > 100000 || ! is_numeric($stock) || $stock < $ligne['quantite']) {
                throw ValidationException::withMessages(['lignes' => 'Prix manquant ou stock insuffisant pour « '.($article['titre'] ?? 'Article').' ».']);
            }
            $prixCentimes = (int) round((float) $prix * 100);
            $sousTotal = $prixCentimes * $ligne['quantite'];
            $total += $sousTotal;
            $lignes[] = [
                'document_id' => $ligne['document_id'],
                'titre' => $article['titre'],
                'quantite' => $ligne['quantite'],
                'prix_unitaire_centimes' => $prixCentimes,
                'sous_total_centimes' => $sousTotal,
            ];
        }

        abort_if($total !== $data['total_attendu_centimes'], 409,
            'Le prix du panier a changé. Revenez aux articles et recréez votre panier.');

        // Une relance réseau du même paiement ne crée pas une deuxième commande.
        DB::table('commandes_demo')->insertOrIgnore([
            'reference' => (string) Str::uuid(),
            'cle_idempotence' => $data['cle_idempotence'],
            'empreinte' => $empreinte,
            'statut' => $data['scenario'] === 'accepte' ? 'paye_demo' : 'refuse_demo',
            'total_centimes' => $total,
            'lignes' => json_encode($lignes),
            'livraison' => json_encode($data['livraison']),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $commande = DB::table('commandes_demo')->where('cle_idempotence', $data['cle_idempotence'])->first();
        abort_unless(hash_equals($commande->empreinte, $empreinte), 409, 'Cette tentative correspond à un autre panier.');
        return $this->resultat($commande);
    }

    private function resultat(object $commande)
    {
        return response()->json([
            'mode' => 'simulation_locale',
            'reference' => $commande->reference,
            'statut' => $commande->statut,
            'total_centimes' => $commande->total_centimes,
            'devise' => 'EUR',
            'lignes' => json_decode($commande->lignes, true),
            'message' => $commande->statut === 'paye_demo'
                ? 'Paiement de test accepté. Aucun débit réel.'
                : 'Carte fictive refusée. Aucun débit réel. Vous pouvez réessayer.',
        ]);
    }
}
