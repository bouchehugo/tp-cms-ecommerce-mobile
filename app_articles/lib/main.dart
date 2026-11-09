import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Adresse du CMS Strapi vue depuis l'émulateur Android
// (10.0.2.2 = le "localhost" du PC)
const String baseUrl = 'http://10.0.2.2:1337';

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
      theme: ThemeData(colorSchemeSeed: Colors.orange),
      home: const ArticlesPage(),
    );
  }
}

class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  late Future<List<Article>> futureArticles;

  @override
  void initState() {
    super.initState();
    futureArticles = fetchArticles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Articles du CMS'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
                  leading: article.imageUrl != null
                      ? Image.network(article.imageUrl!,
                          width: 56, height: 56, fit: BoxFit.cover)
                      : const Icon(Icons.article),
                  title: Text(article.titre),
                  subtitle: Text('Article n°${article.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}