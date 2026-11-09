<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class PanierController extends Controller
{
    public function ajouter(Request $request)
    {
        $data = $request->validate([
            'produit_id' => 'required|integer',
            'quantite' => 'required|integer|min:1',
        ]);

        return response()->json([
            'message' => 'Produit ajouté au panier',
            'panier' => [
                'produit_id' => $data['produit_id'],
                'quantite' => $data['quantite'],
            ],
        ], 201);
    }
}