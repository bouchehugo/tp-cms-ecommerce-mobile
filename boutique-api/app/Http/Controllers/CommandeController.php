<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class CommandeController extends Controller
{
    public function payer(Request $request)
    {
                // Sécurité : on refuse toute donnée de carte bancaire (PCI DSS)
        $champsInterdits = ['card_number', 'numero_carte', 'cvv', 'cvc', 'expiration', 'date_expiration'];
        if ($request->hasAny($champsInterdits)) {
            return response()->json([
                'message' => 'Refusé : aucune donnée de carte bancaire ne doit transiter par notre API.',
            ], 422);
        }

        // Aucune donnée de carte bancaire n'est demandée
        $data = $request->validate([
            'commande_id' => 'required|integer',
            'montant' => 'required|numeric|min:0.01',
        ]);

        // Le paiement est délégué à un prestataire sécurisé (ex : Stripe).
        // Ici on simule la redirection vers sa page de paiement.
        return response()->json([
            'message' => 'Paiement délégué au prestataire sécurisé',
            'commande_id' => $data['commande_id'],
            'montant' => $data['montant'],
            'statut' => 'en_attente_de_paiement',
            'url_paiement' => 'https://paiement.prestataire-securise.example/checkout/' . $data['commande_id'],
        ]);
    }
}