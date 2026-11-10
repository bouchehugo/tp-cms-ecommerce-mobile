# TP B3.2 - CMS, e-commerce et mobile

Hugo BOUCHE & Valentin SCHMITT & Ben TOURE - M1

- `cms-headless` : CMS headless Strapi (articles)
- `boutique-api` : API e-commerce Laravel (panier + paiement)
- `app_articles` : app Flutter qui affiche les articles du CMS
- `livrables` : captures, schéma et PowerPoint

## Lancer le projet

Prérequis : Node.js 24, PHP 8.2 ou supérieur, Composer et Flutter avec Dart
3.13.5 ou supérieur. Les trois services doivent rester démarrés : Strapi
sur le port 1337, Laravel sur le port 8000 et l'application Flutter.

Strapi
```
cd cms-headless
cp .env.example .env
npm install
npm run develop
```
Admin : http://localhost:1337/admin (admin@demo.local / DemoTP-B32!)

Laravel
```
cd boutique-api
cp .env.example .env
composer install
php artisan key:generate
php artisan migrate
php artisan serve
```

Flutter (Strapi doit être lancé)
```
cd app_articles
flutter pub get
flutter run
```

## Prix, quantités et paiement de démonstration

Les articles Strapi possèdent les champs `prix` (euros) et `stock` (entier).
Renseigner ces champs dans Content Manager puis publier les articles.
Un article sans prix ou sans stock ne peut pas être ajouté au panier.
Pour initialiser les deux articles fournis à 19,90 € / 10 unités et
29,90 € / 5 unités, mettre `SEED_DEMO_CATALOG=true` dans `cms-headless/.env`
puis redémarrer Strapi. Cette initialisation ne remplace pas les valeurs déjà renseignées.
Cette option est activée dans le fichier `.env.example` fourni ; si vous avez
déjà un fichier `.env`, ajoutez-y la variable pour initialiser les prix et stocks.

Dans `boutique-api/.env`, définir `PAYMENT_DEMO_ENABLED=true` et
`STRAPI_URL=http://127.0.0.1:1337`, puis lancer :

```powershell
php artisan migrate
php artisan serve --host=127.0.0.1 --port=8000
```

Le panier permet de modifier les quantités dans la limite du stock et affiche
les sous-totaux et le total. Après la livraison, choisir « Accepté » ou « Refusé »
sur l'écran de paiement de test, puis « Simuler le paiement ».
Utiliser des coordonnées de livraison fictives, par exemple `test@example.com`.
La carte affichée est prédéfinie : aucune saisie de carte n'est nécessaire.

Il s'agit d'un simulateur local, sans Stripe ni autre prestataire bancaire,
sans transfert d'argent et sans décrément du stock Strapi. Le serveur relit les
prix et le stock publiés, refuse les quantités insuffisantes ou un total modifié,
et conserve les commandes dans la table `commandes_demo` avec une référence et
le statut `paye_demo` ou `refuse_demo`. Une relance réseau de la même tentative
ne crée pas une deuxième commande. Un refus garde le panier pour réessayer.
Mettre `PAYMENT_DEMO_ENABLED=false` pour désactiver cette route de démonstration.

Pour lancer la même interface dans le navigateur :

```powershell
cd app_articles
flutter run -d chrome
```

Les adresses par défaut utilisent `127.0.0.1` sur le Web et `10.0.2.2` dans
l'émulateur Android. Elles sont personnalisables avec
`--dart-define=STRAPI_URL=...` et `--dart-define=BOUTIQUE_API_URL=...`.

Vérifications : `flutter test`, `flutter analyze` et, depuis `boutique-api`,
`php artisan test --filter=PaiementDemoTest`.
