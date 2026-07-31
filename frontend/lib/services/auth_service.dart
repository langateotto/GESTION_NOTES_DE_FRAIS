import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _keyRole = "user_role";
  static const String _keyToken = "auth_token";

  // Enregistrer le rôle et le token lors d'une connexion réussie
  static Future<void> saveUserSession(String token, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyRole, role);
  }

  // Récupérer le rôle de l'utilisateur (utilisé par main.dart au démarrage)
  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRole);
  }

  // Récupérer le token JWT pour les requêtes API authentifiées
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  // Supprimer les données lors de la déconnexion
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyRole);
  }
  
}