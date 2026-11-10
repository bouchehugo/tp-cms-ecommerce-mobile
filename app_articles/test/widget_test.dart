import 'dart:convert';

import 'package:app_articles/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const article = Article(
  id: 2,
  documentId: 'article-a',
  titre: 'Article A',
  prixCentimes: 1990,
  stock: 2,
);
const livraison = {
  'prenom': 'Test',
  'nom': 'Demo',
  'adresse': '1 rue de Test',
  'complement': '',
  'code_postal': '75001',
  'ville': 'Paris',
  'telephone': '0102030405',
  'email': 'test@example.com',
};

void main() {
  test('Prix décimaux et totaux calculés en centimes', () {
    final produit = Article.fromJson({
      'id': 2,
      'documentId': 'a',
      'titre': 'Test',
      'prix': '19.90',
      'stock': 3,
    });
    expect(produit.prixCentimes, 1990);
    expect(euros(totalPanier([LignePanier(produit, quantite: 3)])), '59,70 €');
    expect(
      Article.fromJson({'id': 3, 'documentId': 'b', 'titre': 'Sans prix'})
          .disponible,
      isFalse,
    );
  });

  testWidgets('Quantités et sous-total sur écran mobile, limite de stock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final panier = {'article-a': LignePanier(article)};
    await tester.pumpWidget(
      MaterialApp(
        home: PanierPage(panier: panier, onPaye: () {}),
      ),
    );
    await tester.tap(find.byTooltip('Augmenter'));
    await tester.pump();
    expect(find.text('Quantité : 2'), findsOneWidget);
    expect(find.text('Total : 39,80 €'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_circle_outline),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Diminuer'));
    await tester.pump();
    expect(find.text('Total : 19,90 €'), findsOneWidget);
    await tester.tap(find.byTooltip('Retirer du panier'));
    await tester.pump();
    expect(find.text('Votre panier est vide'), findsOneWidget);
  });

  testWidgets(
    'Checkout préparé ne signifie pas payé, confirmation serveur requise',
    (tester) async {
      final ancienClient = apiClient;
      addTearDown(() => apiClient = ancienClient);
      final requetes = <Map<String, dynamic>>[];
      var paid = false;
      apiClient = MockClient((request) async {
        if (request.method == 'POST') {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          requetes.add(data);
          return http.Response(
            jsonEncode({
              'mode': 'stripe_test',
              'session_id': 'cs_test_example',
              'checkout_url':
                  'https://checkout.stripe.com/c/pay/cs_test_example',
              'total_centimes': 1990,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'mode': 'stripe_test',
            'reference': 'STRIPE-TEST',
            'statut': paid ? 'paye_test' : 'en_attente',
            'total_centimes': 1990,
            'lignes': [
              {
                'titre': 'Article A',
                'quantite': 1,
                'sous_total_centimes': 1990,
              },
            ],
          }),
          200,
        );
      });
      var paye = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PaiementPage(
            lignes: [LignePanier(article)],
            livraison: livraison,
            onPaye: () => paye = true,
          ),
        ),
      );
      expect(find.text('Accepté'), findsNothing);
      expect(find.text('Refusé'), findsNothing);
      await tester.tap(find.text('Préparer le paiement Stripe'));
      await tester.pumpAndSettle();
      expect(find.text('Ouvrir Stripe Checkout'), findsOneWidget);
      expect(paye, isFalse);
      await tester.tap(find.text('J’ai terminé le paiement · Vérifier'));
      await tester.pumpAndSettle();
      expect(paye, isFalse);
      expect(find.textContaining('pas encore confirmé'), findsOneWidget);
      paid = true;
      await tester.tap(find.text('J’ai terminé le paiement · Vérifier'));
      await tester.pumpAndSettle();
      expect(paye, isTrue);
      expect(find.text('Paiement Stripe confirmé'), findsOneWidget);
      expect(requetes.single['lignes'], [
        {'document_id': 'article-a', 'quantite': 1},
      ]);
      expect(requetes.single.containsKey('scenario'), isFalse);
      expect(requetes.single.containsKey('card_number'), isFalse);
    },
  );

  testWidgets('Clé manquante : erreur affichée, panier conservé', (
    tester,
  ) async {
    final ancienClient = apiClient;
    addTearDown(() => apiClient = ancienClient);
    apiClient = MockClient(
      (_) async => http.Response(
        jsonEncode({'message': 'Stripe n’est pas configuré.'}),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    var paye = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PaiementPage(
          lignes: [LignePanier(article)],
          livraison: livraison,
          onPaye: () => paye = true,
        ),
      ),
    );
    await tester.tap(find.text('Préparer le paiement Stripe'));
    await tester.pumpAndSettle();
    expect(find.text('Stripe n’est pas configuré.'), findsOneWidget);
    expect(paye, isFalse);
    expect(find.text('Préparer le paiement Stripe'), findsOneWidget);
  });
}
