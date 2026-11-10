<?php

use App\Http\Controllers\CommandeController;
use App\Http\Controllers\PanierController;
use App\Http\Controllers\StripeCommandeController;
use Illuminate\Support\Facades\Route;

Route::post('/panier/ajouter', [PanierController::class, 'ajouter']);
Route::post('/commande/payer', [CommandeController::class, 'payer']);
Route::post('/commande/stripe/checkout', [StripeCommandeController::class, 'checkout']);
Route::get('/commande/stripe/{sessionId}', [StripeCommandeController::class, 'statut']);
Route::post('/stripe/webhook', [StripeCommandeController::class, 'webhook']);
