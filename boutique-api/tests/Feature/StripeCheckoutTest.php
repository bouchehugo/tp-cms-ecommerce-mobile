<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class StripeCheckoutTest extends TestCase
{
    use RefreshDatabase;

    private bool $paid = false;
    private bool $tampered = false;
    private bool $offline = false;

    protected function setUp(): void
    {
        parent::setUp();
        config([
            'services.stripe.secret' => 'sk_test_fake_for_unit_tests',
            'services.stripe.webhook_secret' => 'whsec_fake_for_unit_tests',
            'services.stripe.return_url' => 'http://127.0.0.1:8080',
        ]);
        Http::preventStrayRequests();
        Http::fake(function ($request) {
            if (str_contains($request->url(), '/api/articles/')) {
                return Http::response(['data' => [
                    'documentId' => 'article-a', 'titre' => 'Article A', 'prix' => '19.90', 'stock' => 10,
                ]]);
            }
            if ($this->offline) {
                return Http::failedConnection();
            }
            if ($request->method() === 'POST') {
                return Http::response([
                    'id' => 'cs_test_session', 'livemode' => false,
                    'url' => 'https://checkout.stripe.com/c/pay/cs_test_session',
                ]);
            }
            return Http::response($this->stripeSession());
        });
    }

    private function panier(): array
    {
        return [
            'cle_idempotence' => (string) Str::uuid(), 'total_attendu_centimes' => 3980,
            'lignes' => [['document_id' => 'article-a', 'quantite' => 2]],
            'livraison' => [
                'prenom' => 'Test', 'nom' => 'Demo', 'adresse' => '1 rue de Test',
                'complement' => '', 'code_postal' => '75001', 'ville' => 'Paris',
                'telephone' => '0102030405', 'email' => 'test@example.com',
            ],
        ];
    }

    private function stripeSession(): array
    {
        $commande = DB::table('commandes')->first();
        return [
            'id' => 'cs_test_session', 'object' => 'checkout.session', 'livemode' => false,
            'mode' => 'payment', 'currency' => 'eur',
            'client_reference_id' => $commande->reference,
            'metadata' => ['commande_reference' => $commande->reference],
            'amount_total' => $this->tampered ? 1 : 3980,
            'status' => $this->paid ? 'complete' : 'open',
            'payment_status' => $this->paid ? 'paid' : 'unpaid',
        ];
    }

    public function test_checkout_uses_strapi_prices_and_reuses_session(): void
    {
        $data = $this->panier();
        $this->postJson('/api/commande/stripe/checkout', $data)->assertOk()
            ->assertJsonPath('mode', 'stripe_test')->assertJsonPath('total_centimes', 3980);
        $this->postJson('/api/commande/stripe/checkout', $data)->assertOk();
        $this->assertDatabaseCount('commandes', 1);
        $this->assertDatabaseHas('commandes', ['statut' => 'en_attente']);
        Http::assertSent(fn ($r) => $r->url() === 'https://api.stripe.com/v1/checkout/sessions'
            && $r['line_items'][0]['price_data']['unit_amount'] === 1990
            && $r['line_items'][0]['quantity'] === 2
            && $r['success_url'] === 'http://127.0.0.1:8080/?stripe_session={CHECKOUT_SESSION_ID}'
            && $r->hasHeader('Idempotency-Key', 'checkout-'.$data['cle_idempotence'])
            && ! isset($r['livraison']) && ! isset($r['customer_email']));
        Http::assertSentCount(2);
    }

    public function test_only_stripe_confirmation_marks_order_paid(): void
    {
        $this->postJson('/api/commande/stripe/checkout', $this->panier())->assertOk();
        $this->getJson('/api/commande/stripe/cs_test_session?paid=true')
            ->assertOk()->assertJsonPath('statut', 'en_attente');
        $this->paid = true;
        $this->getJson('/api/commande/stripe/cs_test_session')
            ->assertOk()->assertJsonPath('statut', 'paye_test');
        $this->tampered = true;
        $this->getJson('/api/commande/stripe/cs_test_session')->assertStatus(409);
        $this->assertDatabaseHas('commandes', ['statut' => 'paye_test']);
    }

    public function test_missing_or_live_secret_rejected_and_tampered_total_rejected(): void
    {
        foreach (['', 'sk_live_fake_not_a_real_key'] as $secret) {
            config(['services.stripe.secret' => $secret]);
            $this->postJson('/api/commande/stripe/checkout', $this->panier())->assertStatus(503);
        }
        Http::assertNothingSent();
        config(['services.stripe.secret' => 'sk_test_fake_for_unit_tests']);
        $data = $this->panier();
        $data['total_attendu_centimes'] = 1;
        $this->postJson('/api/commande/stripe/checkout', $data)->assertStatus(409);
        $data = $this->panier();
        $data['lignes'][0]['quantite'] = 11;
        $this->postJson('/api/commande/stripe/checkout', $data)->assertUnprocessable();
        $data = $this->panier();
        $data['card_number'] = '4242424242424242';
        $this->postJson('/api/commande/stripe/checkout', $data)->assertUnprocessable();
        $this->assertDatabaseCount('commandes', 0);
    }

    public function test_network_retry_does_not_duplicate_order(): void
    {
        $data = $this->panier();
        $this->offline = true;
        $this->postJson('/api/commande/stripe/checkout', $data)->assertStatus(503);
        $this->assertDatabaseCount('commandes', 1);
        $this->offline = false;
        $this->postJson('/api/commande/stripe/checkout', $data)->assertOk();
        $this->assertDatabaseCount('commandes', 1);
        $data['lignes'][0]['quantite'] = 3;
        $this->postJson('/api/commande/stripe/checkout', $data)->assertStatus(409);
    }

    public function test_webhook_signature_duplicates_and_out_of_order_events(): void
    {
        $this->postJson('/api/commande/stripe/checkout', $this->panier())->assertOk();
        $this->paid = true;
        $event = ['id' => 'evt_test', 'object' => 'event', 'type' => 'checkout.session.completed',
            'livemode' => false, 'data' => ['object' => $this->stripeSession()]];
        $payload = json_encode($event);
        $this->call('POST', '/api/stripe/webhook', [], [], [], [
            'CONTENT_TYPE' => 'application/json', 'HTTP_STRIPE_SIGNATURE' => 'invalid',
        ], $payload)->assertStatus(400);
        $this->assertDatabaseHas('commandes', ['statut' => 'en_attente']);
        $this->signedEvent($event)->assertOk();
        $this->signedEvent($event)->assertOk();
        $this->assertDatabaseCount('commandes', 1);
        $this->assertDatabaseHas('commandes', ['statut' => 'paye_test']);
        $event['type'] = 'checkout.session.expired';
        $event['data']['object']['status'] = 'expired';
        $event['data']['object']['payment_status'] = 'unpaid';
        $this->signedEvent($event)->assertOk();
        $this->assertDatabaseHas('commandes', ['statut' => 'paye_test']);
        $event['livemode'] = true;
        $this->signedEvent($event)->assertStatus(400);
        $event['livemode'] = false;
        $event['data']['object']['amount_total'] = 1;
        $this->signedEvent($event)->assertStatus(409);
    }

    private function signedEvent(array $event)
    {
        $payload = json_encode($event);
        $time = time();
        $signature = hash_hmac('sha256', $time.'.'.$payload, 'whsec_fake_for_unit_tests');
        return $this->call('POST', '/api/stripe/webhook', [], [], [], [
            'CONTENT_TYPE' => 'application/json', 'HTTP_STRIPE_SIGNATURE' => 't='.$time.',v1='.$signature,
        ], $payload);
    }
}
