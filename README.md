# TP B3.2 - CMS, e-commerce et mobile

Hugo BOUCHE & Valentin SCHMITT & Ben TOURE - M1

- `cms-headless` : CMS headless Strapi (articles avec prix et stock)
- `boutique-api` : API e-commerce Laravel (panier + paiement Stripe en mode test)
- `app_articles` : app Flutter (articles, panier, livraison, paiement)
- `livrables` : captures, schéma et PowerPoint

Prérequis : Node.js 24, PHP 8.2+, Composer, Flutter.

## Lancer le projet

Strapi (port 1337)
```
cd cms-headless
cp .env.example .env
npm install
npm run develop
```
Admin : http://localhost:1337/admin (admin@demo.local / DemoTP-B32!)

Laravel (port 8000)
```
cd boutique-api
cp .env.example .env
composer install
php artisan key:generate
php artisan migrate
php artisan serve --host=127.0.0.1 --port=8000
```

Flutter
```
cd app_articles
flutter pub get
flutter run
```
Version navigateur (nécessaire pour le retour Stripe) :
```
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8080
```

## Stripe (mode test)

1. Créer un compte Stripe et rester en mode test.
2. Copier la clé secrète `sk_test_...` dans `STRIPE_SECRET` de `boutique-api/.env`
   (jamais dans Git ni dans l'app).
3. Pour le webhook, avec la [Stripe CLI](https://docs.stripe.com/stripe-cli) :
   ```
   stripe login
   stripe listen --forward-to http://127.0.0.1:8000/api/stripe/webhook
   ```
   Copier le `whsec_...` affiché dans `STRIPE_WEBHOOK_SECRET`, puis `php artisan config:clear`.
4. Dans l'app : ajouter des articles au panier, remplir la livraison, puis payer
   sur la page Stripe avec la carte de test `4242 4242 4242 4242` (date future, CVC `123`).
   Carte refusée : `4000 0000 0000 0002`.

La carte n'est saisie que sur Stripe, elle ne passe jamais par notre API.
Le total est recalculé par le serveur à partir de Strapi, et la commande n'est
marquée payée qu'après confirmation de Stripe (webhook signé ou vérification de la session).

## Tests

```
cd app_articles && flutter test
cd boutique-api && php artisan test
```
