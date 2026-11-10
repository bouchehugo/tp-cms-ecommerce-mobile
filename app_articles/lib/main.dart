import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String baseUrl = String.fromEnvironment(
  'STRAPI_URL',
  defaultValue: kIsWeb ? 'http://127.0.0.1:1337' : 'http://10.0.2.2:1337',
);
const String apiBoutiqueUrl = String.fromEnvironment(
  'BOUTIQUE_API_URL',
  defaultValue: kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000',
);
http.Client apiClient = http.Client();

String euros(int centimes) =>
    '${(centimes / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

String nouvelleTentative() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class Article {
  final int id;
  final String documentId;
  final String titre;
  final String? imageUrl;
  final int prixCentimes;
  final int stock;

  const Article({
    required this.id,
    required this.documentId,
    required this.titre,
    this.imageUrl,
    required this.prixCentimes,
    required this.stock,
  });

  bool get disponible => prixCentimes > 0 && stock > 0;

  factory Article.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    final url = image?['url'] as String?;
    final prix = double.tryParse('${json['prix']}') ?? 0;
    return Article(
      id: json['id'] as int,
      documentId: json['documentId'] as String,
      titre: (json['titre'] ?? '').toString().trim(),
      imageUrl: url == null ? null : Uri.parse(baseUrl).resolve(url).toString(),
      prixCentimes: (prix * 100).round(),
      stock: int.tryParse('${json['stock']}') ?? 0,
    );
  }
}

class LignePanier {
  final Article article;
  int quantite;
  LignePanier(this.article, {this.quantite = 1});
  int get totalCentimes => article.prixCentimes * quantite;
}

int totalPanier(Iterable<LignePanier> lignes) =>
    lignes.fold(0, (total, ligne) => total + ligne.totalCentimes);

String messageApi(http.Response response) {
  try {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final erreurs = data['errors'];
    if (erreurs is Map && erreurs.isNotEmpty) {
      return (erreurs.values.first as List).first.toString();
    }
    return data['message']?.toString() ?? 'Erreur du serveur.';
  } catch (_) {
    return 'Service indisponible (HTTP ${response.statusCode}).';
  }
}

Future<List<Article>> fetchArticles() async {
  final response = await apiClient
      .get(
        Uri.parse(
          '$baseUrl/api/articles?populate=image&pagination[pageSize]=100',
        ),
      )
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) throw Exception(messageApi(response));
  final data = jsonDecode(response.body)['data'] as List;
  return data.map((json) => Article.fromJson(json)).toList();
}

Widget imageArticle(Article article) => article.imageUrl == null
    ? const SizedBox(width: 56, height: 56, child: Icon(Icons.article_outlined))
    : ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          article.imageUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      );

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Articles CMS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.purple),
    home: Uri.base.queryParameters['stripe_session'] != null
        ? RetourStripePage(
            sessionId: Uri.base.queryParameters['stripe_session']!,
          )
        : const ArticlesPage(),
  );
}

class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});
  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  late Future<List<Article>> futureArticles = fetchArticles();
  final Map<String, LignePanier> panier = {};
  final Set<String> ajoutsEnCours = {};

  Future<void> ajouter(Article article) async {
    final quantite = panier[article.documentId]?.quantite ?? 0;
    if (quantite >= article.stock ||
        ajoutsEnCours.contains(article.documentId)) {
      return;
    }
    setState(() => ajoutsEnCours.add(article.documentId));
    try {
      final response = await apiClient
          .post(
            Uri.parse('$apiBoutiqueUrl/api/panier/ajouter'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'produit_id': article.id, 'quantite': 1}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 201) throw Exception(messageApi(response));
      if (!mounted) return;
      setState(
        () => panier.update(
          article.documentId,
          (ligne) => ligne..quantite += 1,
          ifAbsent: () => LignePanier(article),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${article.titre} ajouté au panier')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ajout impossible. Vérifiez que l’API boutique est démarrée.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => ajoutsEnCours.remove(article.documentId));
    }
  }

  Future<void> ouvrirPanier() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PanierPage(
          panier: panier,
          onPaye: () {
            if (mounted) setState(() => panier.clear());
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final nombre = panier.values.fold(0, (t, l) => t + l.quantite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Articles du CMS'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            tooltip: 'Actualiser les articles',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => futureArticles = fetchArticles()),
          ),
          IconButton(
            tooltip: 'Voir le panier',
            onPressed: ouvrirPanier,
            icon: Badge(
              label: Text('$nombre'),
              isLabelVisible: nombre > 0,
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Article>>(
              future: futureArticles,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Catalogue indisponible. Utilisez Actualiser pour réessayer.',
                      ),
                    ),
                  );
                }
                final articles = snapshot.data ?? [];
                if (articles.isEmpty) {
                  return const Center(child: Text('Aucun article publié.'));
                }
                return ListView.builder(
                  itemCount: articles.length,
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    final quantite = panier[article.documentId]?.quantite ?? 0;
                    final activable =
                        article.disponible &&
                        quantite < article.stock &&
                        !ajoutsEnCours.contains(article.documentId);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            imageArticle(article),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    article.titre,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    article.prixCentimes > 0
                                        ? euros(article.prixCentimes)
                                        : 'Prix à renseigner',
                                  ),
                                  Text(
                                    article.stock > 0
                                        ? 'Stock : ${article.stock} · Au panier : $quantite'
                                        : 'Rupture de stock',
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ajouter au panier',
                              icon: const Icon(Icons.add_shopping_cart),
                              onPressed: activable
                                  ? () => ajouter(article)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PanierPage extends StatefulWidget {
  const PanierPage({super.key, required this.panier, required this.onPaye});
  final Map<String, LignePanier> panier;
  final VoidCallback onPaye;
  @override
  State<PanierPage> createState() => _PanierPageState();
}

class _PanierPageState extends State<PanierPage> {
  @override
  Widget build(BuildContext context) {
    final lignes = widget.panier.values.toList();
    final total = totalPanier(lignes);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon panier'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          Expanded(
            child: lignes.isEmpty
                ? const Center(child: Text('Votre panier est vide'))
                : ListView(
                    children: [
                      for (final ligne in lignes)
                        Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    imageArticle(ligne.article),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ligne.article.titre,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          Text(
                                            '${euros(ligne.article.prixCentimes)} / unité',
                                          ),
                                          Text(
                                            'Sous-total : ${euros(ligne.totalCentimes)}',
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Retirer du panier',
                                      onPressed: () => setState(
                                        () => widget.panier.remove(
                                          ligne.article.documentId,
                                        ),
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: 'Diminuer',
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () => setState(() {
                                        if (ligne.quantite > 1) {
                                          ligne.quantite--;
                                        } else {
                                          widget.panier.remove(
                                            ligne.article.documentId,
                                          );
                                        }
                                      }),
                                    ),
                                    Text('Quantité : ${ligne.quantite}'),
                                    IconButton(
                                      tooltip: 'Augmenter',
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onPressed:
                                          ligne.quantite < ligne.article.stock
                                          ? () =>
                                                setState(() => ligne.quantite++)
                                          : null,
                                    ),
                                    Text(
                                      '/ ${ligne.article.stock} disponibles',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: lignes.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total : ${euros(total)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text('Livraison offerte · Montant de démonstration'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Continuer vers la livraison'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CommandePage(
                              lignes: lignes
                                  .map(
                                    (l) => LignePanier(
                                      l.article,
                                      quantite: l.quantite,
                                    ),
                                  )
                                  .toList(),
                              onPaye: widget.onPaye,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class CommandePage extends StatefulWidget {
  const CommandePage({super.key, required this.lignes, required this.onPaye});
  final List<LignePanier> lignes;
  final VoidCallback onPaye;
  @override
  State<CommandePage> createState() => _CommandePageState();
}

class _CommandePageState extends State<CommandePage> {
  final formKey = GlobalKey<FormState>();
  final champs = {
    'prenom': TextEditingController(),
    'nom': TextEditingController(),
    'adresse': TextEditingController(),
    'complement': TextEditingController(),
    'code_postal': TextEditingController(),
    'ville': TextEditingController(),
    'telephone': TextEditingController(),
    'email': TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in champs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget champ(
    String cle,
    String libelle, {
    bool facultatif = false,
    TextInputType clavier = TextInputType.text,
    int maxLength = 100,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: champs[cle],
        keyboardType: clavier,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: facultatif ? '$libelle (facultatif)' : libelle,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        validator: (valeur) {
          final texte = valeur?.trim() ?? '';
          if (!facultatif && texte.isEmpty) return 'Ce champ est obligatoire';
          if (cle == 'email' &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(texte)) {
            return 'Indiquez une adresse e-mail valide';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Livraison'),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          Text('Récapitulatif', style: Theme.of(context).textTheme.titleLarge),
          for (final ligne in widget.lignes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${ligne.article.titre} × ${ligne.quantite} — ${euros(ligne.totalCentimes)}',
              ),
            ),
          Text(
            'Total : ${euros(totalPanier(widget.lignes))}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 12),
          champ('prenom', 'Prénom'),
          champ('nom', 'Nom'),
          champ(
            'adresse',
            'Adresse',
            clavier: TextInputType.streetAddress,
            maxLength: 255,
          ),
          champ(
            'complement',
            'Complément d’adresse',
            facultatif: true,
            maxLength: 255,
          ),
          champ('code_postal', 'Code postal', maxLength: 20),
          champ('ville', 'Ville'),
          champ(
            'telephone',
            'Téléphone',
            clavier: TextInputType.phone,
            maxLength: 30,
          ),
          champ(
            'email',
            'E-mail',
            clavier: TextInputType.emailAddress,
            maxLength: 255,
          ),
          FilledButton.icon(
            icon: const Icon(Icons.credit_card),
            label: const Text('Continuer vers le paiement de test'),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaiementPage(
                    lignes: widget.lignes,
                    livraison: champs.map(
                      (cle, controller) =>
                          MapEntry(cle, controller.text.trim()),
                    ),
                    onPaye: widget.onPaye,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class PaiementPage extends StatefulWidget {
  const PaiementPage({
    super.key,
    required this.lignes,
    required this.livraison,
    required this.onPaye,
  });
  final List<LignePanier> lignes;
  final Map<String, String> livraison;
  final VoidCallback onPaye;
  @override
  State<PaiementPage> createState() => _PaiementPageState();
}

class _PaiementPageState extends State<PaiementPage> {
  String cle = nouvelleTentative();
  String? sessionId;
  Uri? checkoutUrl;
  bool enCours = false;
  bool verification = false;
  bool expire = false;
  String? erreur;
  String? information;
  Timer? suivi;

  @override
  void dispose() {
    suivi?.cancel();
    super.dispose();
  }

  Future<void> payer() async {
    if (enCours) return;
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      final response = await apiClient
          .post(
            Uri.parse('$apiBoutiqueUrl/api/commande/stripe/checkout'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'cle_idempotence': cle,
              'total_attendu_centimes': totalPanier(widget.lignes),
              'lignes': widget.lignes
                  .map(
                    (l) => {
                      'document_id': l.article.documentId,
                      'quantite': l.quantite,
                    },
                  )
                  .toList(),
              'livraison': widget.livraison,
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) throw Exception(messageApi(response));
      final resultat = jsonDecode(response.body) as Map<String, dynamic>;
      final url = Uri.parse(resultat['checkout_url'] as String);
      if (resultat['mode'] != 'stripe_test' ||
          url.scheme != 'https' ||
          url.host != 'checkout.stripe.com' ||
          !(resultat['session_id'] as String).startsWith('cs_test_')) {
        throw Exception('Session Stripe de test invalide.');
      }
      if (!mounted) return;
      setState(() {
        sessionId = resultat['session_id'] as String;
        checkoutUrl = url;
        expire = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => erreur = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => enCours = false);
    }
  }

  Future<void> ouvrirStripe() async {
    try {
      // Un second clic ouvre la page : évite le blocage des fenêtres après une requête réseau.
      final ouvert = await launchUrl(
        checkoutUrl!,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!ouvert) throw Exception('Le navigateur n’a pas pu ouvrir Stripe.');
      suivi?.cancel();
      suivi = Timer.periodic(
        const Duration(seconds: 4),
        (_) => verifier(silencieux: true),
      );
    } catch (e) {
      if (mounted) {
        setState(() => erreur = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> verifier({bool silencieux = false}) async {
    if (verification || sessionId == null || !mounted) return;
    setState(() {
      verification = true;
      if (!silencieux) erreur = null;
    });
    try {
      final resultat = await verifierSessionStripe(sessionId!);
      if (!mounted) return;
      if (resultat['statut'] == 'paye_test') {
        suivi?.cancel();
        widget.onPaye();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ConfirmationPage(resultat: resultat),
          ),
          (route) => route.isFirst,
        );
      } else if (resultat['statut'] == 'expire') {
        suivi?.cancel();
        setState(() {
          expire = true;
          erreur = 'La session a expiré. Créez une nouvelle tentative.';
        });
      } else if (!silencieux) {
        setState(
          () => information = 'Stripe n’a pas encore confirmé le paiement. Vous pouvez retourner sur Checkout.',
        );
      }
    } catch (e) {
      if (mounted && !silencieux) {
        setState(() => erreur = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => verification = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !enCours,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Paiement Stripe'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'À régler : ${euros(totalPanier(widget.lignes))}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          for (final ligne in widget.lignes)
            Text(
              '${ligne.article.titre} × ${ligne.quantite} — ${euros(ligne.totalCentimes)}',
            ),
          const SizedBox(height: 24),
          const Card(
            child: ListTile(
              leading: Icon(Icons.credit_card),
              title: Text('Stripe Checkout · Mode test'),
              subtitle: Text(
                'La carte se saisit uniquement sur la page sécurisée de Stripe.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SelectableText(
            'Carte de test : 4242 4242 4242 4242\nExpiration : 12/34 · CVC : 123',
          ),
          const SizedBox(height: 24),
          if (erreur != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                erreur!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (information != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(information!),
            ),
          if (sessionId == null || expire)
            FilledButton.icon(
              onPressed: enCours
                  ? null
                  : () {
                      if (expire) {
                        cle = nouvelleTentative();
                        sessionId = null;
                        checkoutUrl = null;
                      }
                      payer();
                    },
              icon: const Icon(Icons.lock_outline),
              label: Text(
                enCours
                    ? 'Préparation…'
                    : expire
                    ? 'Nouvelle tentative'
                    : 'Préparer le paiement Stripe',
              ),
            )
          else ...[
            FilledButton.icon(
              onPressed: ouvrirStripe,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ouvrir Stripe Checkout'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: verification ? null : verifier,
              child: Text(
                verification
                    ? 'Vérification…'
                    : 'J’ai terminé le paiement · Vérifier',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Si vous annulez ou si la carte est refusée, votre panier est conservé.',
            ),
          ],
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>> verifierSessionStripe(String sessionId) async {
  final response = await apiClient
      .get(
        Uri.parse(
          '$apiBoutiqueUrl/api/commande/stripe/${Uri.encodeComponent(sessionId)}',
        ),
        headers: {'Accept': 'application/json'},
      )
      .timeout(const Duration(seconds: 35));
  if (response.statusCode != 200) throw Exception(messageApi(response));
  final resultat = jsonDecode(response.body) as Map<String, dynamic>;
  if (resultat['mode'] != 'stripe_test') {
    throw Exception('Réponse Stripe inattendue.');
  }
  return resultat;
}

class RetourStripePage extends StatefulWidget {
  const RetourStripePage({super.key, required this.sessionId});
  final String sessionId;
  @override
  State<RetourStripePage> createState() => _RetourStripePageState();
}

class _RetourStripePageState extends State<RetourStripePage> {
  late Future<Map<String, dynamic>> verification = verifierSessionStripe(
    widget.sessionId,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: verification,
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data!['statut'] == 'paye_test') {
        return ConfirmationPage(resultat: snapshot.data!);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Vérification Stripe')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text(
                  snapshot.hasError
                      ? snapshot.error.toString().replaceFirst(
                          'Exception: ',
                          '',
                        )
                      : 'Paiement pas encore confirmé par Stripe.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() {
                    verification = verifierSessionStripe(widget.sessionId);
                  }),
                  child: const Text('Vérifier à nouveau'),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ArticlesPage()),
                ),
                child: const Text('Retour aux articles'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ConfirmationPage extends StatelessWidget {
  const ConfirmationPage({super.key, required this.resultat});
  final Map<String, dynamic> resultat;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confirmation Stripe')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle_outline, color: Colors.green, size: 72),
        const SizedBox(height: 16),
        Text(
          'Paiement Stripe confirmé',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Paiement de test confirmé par Stripe.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SelectableText('Référence : ${resultat['reference']}'),
        const SizedBox(height: 16),
        for (final ligne in resultat['lignes'] as List)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${ligne['titre']} × ${ligne['quantite']} — ${euros(ligne['sous_total_centimes'] as int)}',
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Total payé en mode test : ${euros(resultat['total_centimes'] as int)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ArticlesPage()),
            (route) => false,
          ),
          child: const Text('Retour aux articles'),
        ),
      ],
    ),
  );
}
