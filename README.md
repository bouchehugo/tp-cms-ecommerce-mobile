# TP B3.2 - CMS, e-commerce et mobile

Hugo BOUCHE et Valentin - M1

- `cms-headless` : CMS headless Strapi (articles)
- `boutique-api` : API e-commerce Laravel (panier + paiement)
- `app_articles` : app Flutter qui affiche les articles du CMS
- `livrables` : captures, schéma et PowerPoint

## Lancer le projet

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
php artisan serve
```

Flutter (Strapi doit être lancé)
```
cd app_articles
flutter pub get
flutter run
```
