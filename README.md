# TP B3.2 - CMS, e-commerce et mobile

Hugo BOUCHE & Valentin SCHMITT & Ben Toure - M1

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

## Prix, quantités et Stripe en mode test

Les articles Strapi possèdent les champs `prix` (euros) et `stock` (entier).
Renseigner ces champs dans Content Manager puis publier les articles.
Un article sans prix ou sans stock ne peut pas être ajouté au panier.
Pour initialiser les deux articles fournis à 19,90 € / 10 unités et
29,90 € / 5 unités, mettre `SEED_DEMO_CATALOG=true` dans `cms-headless/.env`
puis redémarrer Strapi. Cette initialisation ne remplace pas les valeurs déjà renseignées.
Cette option est activée dans le fichier `.env.example` fourni ; si vous avez
déjà un fichier `.env`, ajoutez-y la variable pour initialiser les prix et stocks.

Dans `boutique-api/.env`, configurer uniquement côté serveur :

```dotenv
STRAPI_URL=http://127.0.0.1:1337
PAYMENT_DEMO_ENABLED=false
STRIPE_SECRET=
STRIPE_WEBHOOK_SECRET=
STRIPE_RETURN_URL=http://127.0.0.1:8080
```

Mettre la clé secrète de **test** du compte Stripe (`sk_test_…`) dans
`STRIPE_SECRET`. Ne jamais la mettre dans Flutter, le chat ou Git.
Aucune clé publique n'est nécessaire pour cette redirection vers Checkout.
Le serveur refuse les clés de production et les sessions en mode réel.

```powershell
cd boutique-api
composer install
php artisan key:generate
php artisan migrate
php artisan config:clear
php artisan serve --host=127.0.0.1 --port=8000
```

Conserver le fichier `.env` et sa clé d'application si le projet est déjà installé :
ne relancer `key:generate` que pour une première installation.

### Webhook Stripe local

Installer la [Stripe CLI officielle](https://docs.stripe.com/stripe-cli), puis
la connecter au même compte et au même environnement de test que la clé :

```powershell
stripe login
stripe listen --events checkout.session.completed,checkout.session.expired,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed --forward-to http://127.0.0.1:8000/api/stripe/webhook
```

Copier le secret `whsec_…` affiché par `stripe listen` dans
`STRIPE_WEBHOOK_SECRET` du fichier `boutique-api/.env`, puis exécuter
`php artisan config:clear`. Laisser cette commande en cours pendant le test.
Le corps brut et la signature Stripe sont vérifiés avec le SDK officiel.
Configurer un webhook HTTPS dans Stripe pour un serveur distant.
Le webhook confirme la commande même si le client ferme la page de retour.

### Tester le parcours

Pour le navigateur, utiliser un port fixe correspondant à `STRIPE_RETURN_URL` :

```powershell
cd app_articles
flutter pub get
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8080
```

1. Ajouter les articles et choisir les quantités.
2. Renseigner la livraison, puis « Préparer le paiement Stripe ».
3. Cliquer sur « Ouvrir Stripe Checkout » : la page officielle Stripe s'ouvre
   dans un autre onglet (ou le navigateur système sur Android).
4. Saisir **uniquement dans Stripe** la carte de test `4242 4242 4242 4242`,
   une expiration future (par exemple `12/34`) et le CVC `123`.
   Pour un refus, utiliser `4000 0000 0000 0002`.
5. Après paiement, la page de retour vérifie la session côté serveur.
   Dans l'application d'origine, le statut est aussi vérifié automatiquement,
   ou avec « J’ai terminé le paiement · Vérifier ».

Les cartes sont documentées dans la [documentation Stripe de test](https://docs.stripe.com/testing).
Utiliser des coordonnées fictives de livraison pour les essais.
Un refus ou une annulation ne vide pas le panier et ne marque pas la commande payée.
Les données de carte ne transitent jamais par l'API Laravel.

Le serveur calcule le total à partir de Strapi, crée une session Checkout
avec une clé d'idempotence et enregistre la commande dans **`commandes`**.
Statuts : `en_attente`, `paye_test`, `expire`.
Seuls un webhook Stripe signé ou la lecture serveur de la session auprès
de Stripe peuvent confirmer le paiement, après vérification du mode test,
de la référence, du montant, de la devise et du statut.
Un paramètre d'URL de retour ne suffit jamais.
Les appels répétés et les webhooks reçus plusieurs fois ne créent pas de doublon.
Les essais ne décrémentent pas le stock Strapi.

L'ancien simulateur reste isolé dans `commandes_demo`, pour les anciens tests :
sa route n'est plus utilisée par l'application et elle est désactivée par défaut
(`PAYMENT_DEMO_ENABLED=false`). Il ne doit pas être présenté comme un paiement Stripe.

Les adresses par défaut utilisent `127.0.0.1` sur le Web et `10.0.2.2` dans
l'émulateur Android. Elles sont personnalisables avec
`--dart-define=STRAPI_URL=...` et `--dart-define=BOUTIQUE_API_URL=...`.
`STRIPE_RETURN_URL` reste une URL de retour navigateur configurée par le serveur.

Vérifications : `flutter test`, `flutter analyze` et, depuis `boutique-api`,
`php artisan test`. Les tests automatisés Stripe utilisent des réponses API
contrôlées et des signatures de webhook de test ; ils ne remplacent pas un
paiement manuel dans votre véritable Sandbox Stripe.
