import 'package:flutter/material.dart';

class BaseScreen extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const BaseScreen({
    Key? key,
    required this.title,
    required this.child,
    this.actions,
    this.floatingActionButton,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Le dégradé exact inspiré de votre capture d'écran
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E3C72), // Bleu nuit en haut
            Color(0xFF2A5298), // Bleu intermédiaire
            Color(0xFF0F2027), // Sombre sur les bords/bas
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent, // Indispensable pour voir le dégradé
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: actions,
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600), // Largeur maximale pour garder l'effet "carte" élégant
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: child, // Le contenu spécifique de votre écran viendra ici
            ),
          ),
        ),
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}