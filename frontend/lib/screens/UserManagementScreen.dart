import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'base_screen.dart';

class UserManagementScreen extends StatelessWidget {
  final ApiService apiService;
  
  const UserManagementScreen({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    // On utilise BaseScreen pour uniformiser le fond et le style de la carte
    return BaseScreen(
      title: "Gestion des Utilisateurs",
      actions: [
        // Bouton de déconnexion dans l'AppBar du BaseScreen
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.red),
          tooltip: "Se déconnecter",
          onPressed: () => _confirmLogout(context),
        ),
      ],
      child: FutureBuilder<List<dynamic>>(
        future: apiService.getAllUsers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          final users = snapshot.data!;
          if (users.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: Text("Aucun utilisateur trouvé.")),
            );
          }

          // On utilise ListView.builder avec shrinkWrap et physics pour l'intégrer proprement dans la carte du BaseScreen
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  title: Text(
                    user['nom_user'] ?? 'Sans nom',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Rôle : ${user['role'] ?? 'employe'}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.lock_reset, color: Colors.blue),
                    tooltip: "Réinitialiser le mot de passe",
                    onPressed: () => _showResetPasswordDialog(context, user),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Boîte de dialogue de confirmation pour la déconnexion
  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment vous déconnecter ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService.logout(); 

              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoginScreen(apiService: apiService),
                  ),
                  (route) => false,
                );
              }
            },
            child: const Text("Se déconnecter", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext context, dynamic user) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Reset mot de passe : ${user['nom_user']}"),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Nouveau mot de passe",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Veuillez entrer un mot de passe")),
                );
                return;
              }

              bool success = await apiService.resetUserPassword(
                user['id'], 
                controller.text,
              );
              
              if (success) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Mot de passe mis à jour avec succès !")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("❌ Erreur lors de la mise à jour")),
                );
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }
}