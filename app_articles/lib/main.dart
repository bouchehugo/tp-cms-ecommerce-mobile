import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Adresse du CMS Strapi vue depuis l'émulateur Android
// (10.0.2.2 = le "localhost" du PC)
const String baseUrl = 'http://10.0.2.2:1337';

// Adresse de l'API e-commerce Laravel (EXO 2), lancée avec "php artisan serve"
const String apiBoutiqueUrl = 'http://10.0.2.2:8000';

// Modèle : un article du CMS
class Article {
  final int id;
  final String titre;
  final String? imageUrl;

  Article({required this.id, required this.titre, this.imageUrl});

  factory Article.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    return Article(
      id: json['id'],
      titre: (json['titre'] ?? '').toString().trim(),
      imageUrl: image != null ? '$baseUrl${image['url']}' : null,
    );
  }
}

// Modèle : une ligne du panier (un article et sa quantité)
class LignePanier {
  final Article article;
  int quantite;

  LignePanier(this.article, {this.quantite = 1});
}

// Appel de l'API REST du CMS headless (EXO 1)
Future<List<Article>> fetchArticles() async {
  final res = await http.get(
    Uri.parse('$baseUrl/api/articles?populate=image'),
  );
  if (res.statusCode != 200) {
    throw Exception('Erreur API : ${res.statusCode}');
  }
  final List data = jsonDecode(res.body)['data'];
  return data.map((json) => Article.fromJson(json)).toList();
}

// Appel de la route Laravel "ajouter au panier" (EXO 2)
Future<void> ajouterAuPanier(int produitId, {int quantite = 1}) async {
  final res = await http.post(
    Uri.parse('$apiBoutiqueUrl/api/panier/ajouter'),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: jsonEncode({'produit_id': produitId, 'quantite': quantite}),
  );
  if (res.statusCode != 201) {
    throw Exception('Erreur panier : ${res.statusCode}');
  }
}

// Image d'un article, ou une icône s'il n'en a pas
Widget imageArticle(Article article) {
  return article.imageUrl != null
      ? Image.network(article.imageUrl!,
          width: 56, height: 56, fit: BoxFit.cover)
      : const Icon(Icons.article);
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Articles CMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.purple),
      home: const ArticlesPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 1 : la liste des articles
// ---------------------------------------------------------------------------
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  late Future<List<Article>> futureArticles;

  // Le panier : une ligne par article (clé = id de l'article)
  final Map<int, LignePanier> panier = {};

  int get nbProduitsPanier =>
      panier.values.fold(0, (total, ligne) => total + ligne.quantite);

  @override
  void initState() {
    super.initState();
    futureArticles = fetchArticles();
  }

  // Bouton "ajouter au panier" : appelle l'API puis met à jour le panier
  Future<void> onAjouterAuPanier(Article article) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ajouterAuPanier(article.id);
      setState(() {
        panier.update(
          article.id,
          (ligne) => ligne..quantite += 1,
          ifAbsent: () => LignePanier(article),
        );
      });
      messenger.showSnackBar(
        SnackBar(content: Text('${article.titre} ajouté au panier')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Impossible d\'ajouter au panier : $e')),
      );
    }
  }

  // Ouvre l'écran du panier, puis rafraîchit le compteur au retour
  Future<void> ouvrirPanier() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PanierPage(panier: panier)),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Articles du CMS'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            tooltip: 'Voir le panier',
            onPressed: ouvrirPanier,
            icon: Badge(
              label: Text('$nbProduitsPanier'),
              isLabelVisible: nbProduitsPanier > 0,
              child: const Icon(Icons.shopping_cart),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<Article>>(
        future: futureArticles,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final articles = snapshot.data!;
          // Liste des articles récupérés (ListView)
          return ListView.builder(
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: imageArticle(article),
                  title: Text(article.titre),
                  subtitle: Text('Article n°${article.id}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_shopping_cart),
                    tooltip: 'Ajouter au panier',
                    onPressed: () => onAjouterAuPanier(article),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 2 : le contenu du panier
// ---------------------------------------------------------------------------
class PanierPage extends StatefulWidget {
  const PanierPage({super.key, required this.panier});

  final Map<int, LignePanier> panier;

  @override
  State<PanierPage> createState() => _PanierPageState();
}

class _PanierPageState extends State<PanierPage> {
  void retirer(LignePanier ligne) {
    setState(() => widget.panier.remove(ligne.article.id));
  }

  void augmenter(LignePanier ligne) {
    setState(() => ligne.quantite++);
  }

  // À 1, le bouton "−" retire l'article du panier
  void diminuer(LignePanier ligne) {
    setState(() {
      if (ligne.quantite > 1) {
        ligne.quantite--;
      } else {
        widget.panier.remove(ligne.article.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lignes = widget.panier.values.toList();
    final total = lignes.fold(0, (t, ligne) => t + ligne.quantite);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon panier'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: lignes.isEmpty
          ? const Center(child: Text('Votre panier est vide'))
          : ListView(
              children: [
                for (final ligne in lignes)
                  Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: imageArticle(ligne.article),
                      title: Text(ligne.article.titre),
                      subtitle: Text('Quantité : ${ligne.quantite}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: 'Diminuer',
                            onPressed: () => diminuer(ligne),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Augmenter',
                            onPressed: () => augmenter(ligne),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Retirer du panier',
                            onPressed: () => retirer(ligne),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: lignes.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.shopping_bag),
                  label: Text('Passer la commande ($total produits)'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommandePage(lignes: lignes),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Écran 3 : les informations du client avant le paiement
// ---------------------------------------------------------------------------
class CommandePage extends StatefulWidget {
  const CommandePage({super.key, required this.lignes});

  final List<LignePanier> lignes;

  @override
  State<CommandePage> createState() => _CommandePageState();
}

class _CommandePageState extends State<CommandePage> {
  final formKey = GlobalKey<FormState>();
  final prenomController = TextEditingController();
  final nomController = TextEditingController();
  final adresseController = TextEditingController();
  final complementController = TextEditingController();
  final codePostalController = TextEditingController();
  final villeController = TextEditingController();
  final telephoneController = TextEditingController();
  final emailController = TextEditingController();

  @override
  void dispose() {
    prenomController.dispose();
    nomController.dispose();
    adresseController.dispose();
    complementController.dispose();
    codePostalController.dispose();
    villeController.dispose();
    telephoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  String? champObligatoire(String? valeur) {
    if (valeur == null || valeur.trim().isEmpty) {
      return 'Ce champ est obligatoire';
    }
    return null;
  }

  // Un champ du formulaire de livraison
  Widget champ(
    String libelle,
    TextEditingController controller, {
    bool obligatoire = true,
    TextInputType clavier = TextInputType.text,
    TextCapitalization majuscules = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: clavier,
        textCapitalization: majuscules,
        decoration: InputDecoration(
          labelText: obligatoire ? libelle : '$libelle (facultatif)',
          border: const OutlineInputBorder(),
        ),
        validator: obligatoire ? champObligatoire : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titre = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Livraison'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Récapitulatif', style: titre),
            const SizedBox(height: 8),
            for (final ligne in widget.lignes)
              Text('• ${ligne.article.titre} × ${ligne.quantite}'),
            const SizedBox(height: 24),
            Text('Informations de livraison', style: titre),
            const SizedBox(height: 12),
            champ('Prénom', prenomController,
                majuscules: TextCapitalization.words),
            champ('Nom', nomController, majuscules: TextCapitalization.words),
            champ('Adresse', adresseController,
                clavier: TextInputType.streetAddress),
            champ('Complément d\'adresse', complementController,
                obligatoire: false),
            champ('Code postal', codePostalController,
                clavier: TextInputType.number),
            champ('Ville', villeController,
                majuscules: TextCapitalization.words),
            champ('Téléphone', telephoneController,
                clavier: TextInputType.phone),
            champ('E-mail', emailController,
                clavier: TextInputType.emailAddress),
            const SizedBox(height: 12),
            // Le paiement n'est pas encore branché : le bouton ne fait rien.
            // Aucune donnée de carte bancaire n'est demandée dans l'application.
            FilledButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text('Payer'),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
