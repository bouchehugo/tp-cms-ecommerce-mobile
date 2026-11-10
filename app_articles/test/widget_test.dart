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

  testWidgets('Refus puis acceptation du paiement, sans carte transmise', (
    tester,
  ) async {
    final ancienClient = apiClient;
    addTearDown(() => apiClient = ancienClient);
    final requetes = <Map<String, dynamic>>[];
    apiClient = MockClient((request) async {
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      requetes.add(data);
      return http.Response(
        jsonEncode({
          'mode': 'simulation_locale',
          'reference': 'DEMO-TEST',
          'statut': data['scenario'] == 'refuse' ? 'refuse_demo' : 'paye_demo',
          'message': 'Carte fictive refusée. Réessayez.',
          'total_centimes': 1990,
          'lignes': [
            {'titre': 'Article A', 'quantite': 1, 'sous_total_centimes': 1990},
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
    await tester.tap(find.text('Refusé'));
    await tester.pump();
    await tester.tap(find.text('Simuler le paiement de 19,90 €'));
    await tester.pumpAndSettle();
    expect(paye, isFalse);
    expect(find.text('Carte fictive refusée. Réessayez.'), findsOneWidget);
    await tester.tap(find.text('Accepté'));
    await tester.pump();
    await tester.tap(find.text('Simuler le paiement de 19,90 €'));
    await tester.pumpAndSettle();
    expect(paye, isTrue);
    expect(find.text('Paiement de test accepté'), findsOneWidget);
    expect(find.text('Total simulé : 19,90 €'), findsOneWidget);
    expect(
      requetes[0]['cle_idempotence'],
      isNot(requetes[1]['cle_idempotence']),
    );
    expect(requetes[1]['lignes'], [
      {'document_id': 'article-a', 'quantite': 1},
    ]);
    expect(requetes[1].containsKey('card_number'), isFalse);
  });
}
