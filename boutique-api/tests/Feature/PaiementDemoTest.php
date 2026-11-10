<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class PaiementDemoTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.paiement_demo' => true]);
        Http::preventStrayRequests();
        Http::fake([
            '*/api/articles/article-a' => Http::response(['data' => [
                'documentId' => 'article-a', 'titre' => 'Article A', 'prix' => '19.90', 'stock' => 10,
            ]]),
            '*/api/articles/article-b' => Http::response(['data' => [
                'documentId' => 'article-b', 'titre' => 'Article B', 'prix' => '29.90', 'stock' => 5,
            ]]),
        ]);
    }

    private function panier(): array
    {
        return [
            'cle_idempotence' => (string) Str::uuid(),
            'scenario' => 'accepte',
            'total_attendu_centimes' => 6970,
            'lignes' => [
                ['document_id' => 'article-a', 'quantite' => 2],
                ['document_id' => 'article-b', 'quantite' => 1],
            ],
            'livraison' => [
                'prenom' => 'Test', 'nom' => 'Demo', 'adresse' => '1 rue de Test',
                'complement' => '', 'code_postal' => '75001', 'ville' => 'Paris',
                'telephone' => '0102030405', 'email' => 'test@example.com',
            ],
        ];
    }

    public function test_total_from_catalogue_and_order_persisted_only_once(): void
    {
        $data = $this->panier();
        $data['montant'] = 0.01; // Un montant client ne détermine jamais le prix.
        $first = $this->postJson('/api/commande/payer', $data)->assertOk()
            ->assertJsonPath('mode', 'simulation_locale')
            ->assertJsonPath('total_centimes', 6970)
            ->assertJsonPath('statut', 'paye_demo')
            ->assertJsonPath('lignes.0.sous_total_centimes', 3980);
        $this->postJson('/api/commande/payer', $data)->assertOk()
            ->assertJsonPath('reference', $first->json('reference'));
        $this->assertDatabaseCount('commandes_demo', 1);
        Http::assertSentCount(2);
    }

    public function test_declined_payment_can_be_retried_with_a_new_key(): void
    {
        $data = $this->panier();
        $data['scenario'] = 'refuse';
        $this->postJson('/api/commande/payer', $data)->assertOk()->assertJsonPath('statut', 'refuse_demo');
        $data['scenario'] = 'accepte';
        $data['cle_idempotence'] = (string) Str::uuid();
        $this->postJson('/api/commande/payer', $data)->assertOk()->assertJsonPath('statut', 'paye_demo');
        $this->assertDatabaseCount('commandes_demo', 2);
    }

    public function test_reusing_key_for_another_cart_is_rejected(): void
    {
        $data = $this->panier();
        $this->postJson('/api/commande/payer', $data)->assertOk();
        $data['lignes'][0]['quantite'] = 3;
        $this->postJson('/api/commande/payer', $data)->assertStatus(409);
        $this->assertDatabaseCount('commandes_demo', 1);
    }

    public function test_stock_prices_empty_cart_and_missing_address_are_checked(): void
    {
        $data = $this->panier();
        $data['lignes'][0]['quantite'] = 11;
        $this->postJson('/api/commande/payer', $data)->assertUnprocessable();
        $data = $this->panier();
        $data['total_attendu_centimes'] = 1;
        $this->postJson('/api/commande/payer', $data)->assertStatus(409);
        $data = $this->panier();
        $data['lignes'] = [];
        $data['livraison']['email'] = 'invalide';
        $this->postJson('/api/commande/payer', $data)->assertUnprocessable()
            ->assertJsonValidationErrors(['lignes', 'livraison.email']);
        $this->assertDatabaseCount('commandes_demo', 0);
    }

    public function test_missing_article_or_unavailable_catalogue_cannot_be_paid(): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::fake(['*' => Http::response(['data' => null], 404)]);
        $this->postJson('/api/commande/payer', $this->panier())->assertUnprocessable();
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::fake(['*' => Http::failedConnection()]);
        $this->postJson('/api/commande/payer', $this->panier())->assertStatus(503);
        $this->assertDatabaseCount('commandes_demo', 0);
    }

    public function test_card_fields_are_rejected_and_demo_can_be_disabled(): void
    {
        $data = $this->panier();
        $data['paiement'] = ['card_number' => '4242424242424242'];
        $this->postJson('/api/commande/payer', $data)->assertUnprocessable();
        config(['services.paiement_demo' => false]);
        $this->postJson('/api/commande/payer', $this->panier())->assertForbidden();
        $this->assertDatabaseCount('commandes_demo', 0);
    }
}
