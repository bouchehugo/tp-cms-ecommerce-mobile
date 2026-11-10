<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('commandes_demo', function (Blueprint $table) {
            $table->id();
            $table->uuid('reference')->unique();
            $table->uuid('cle_idempotence')->unique();
            $table->string('empreinte');
            $table->string('statut');
            $table->unsignedBigInteger('total_centimes');
            $table->json('lignes');
            $table->json('livraison');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('commandes_demo');
    }
};
