<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('commandes', function (Blueprint $table) {
            $table->id();
            $table->uuid('reference')->unique();
            $table->uuid('cle_idempotence')->unique();
            $table->string('empreinte');
            $table->string('statut')->default('en_attente');
            $table->unsignedBigInteger('total_centimes');
            $table->json('lignes');
            $table->json('livraison');
            $table->string('stripe_session_id')->nullable()->unique();
            $table->text('stripe_url')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('commandes');
    }
};
