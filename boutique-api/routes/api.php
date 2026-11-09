<?php

use App\Http\Controllers\CommandeController;
use App\Http\Controllers\PanierController;
use Illuminate\Support\Facades\Route;

Route::post('/panier/ajouter', [PanierController::class, 'ajouter']);
Route::post('/commande/payer', [CommandeController::class, 'payer']);