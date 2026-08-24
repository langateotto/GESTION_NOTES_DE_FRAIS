import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'package:flutter/foundation.dart';


class ApiService {
  final String baseUrl = "http://127.0.0.1:8000";

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        body: {
          "username": username,
          "password": password,
        },
      );

      print("📡 [LOGIN] Status Code : ${response.statusCode}");
      print("📦 [LOGIN] Response Body : ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String token = data['access_token'];
        
        String role = data['role'] ?? 'employe'; 
        // Récupération de la valeur must_change_password (false par défaut si absente)
        bool mustChangePassword = data['must_change_password'] ?? false;
        
        print("👤 [LOGIN] Rôle détecté : $role | Doit changer le mot de passe : $mustChangePassword");

        await AuthService.saveUserSession(token, role);

        return {
          "success": true, 
          "role": role,
          "must_change_password": mustChangePassword,
        };
      } else {
        print("❌ [LOGIN] Échec de la connexion.");
        return {"success": false, "role": null, "must_change_password": false};
      }
    } catch (e) {
      print("🔥 [LOGIN] Erreur de connexion : $e");
      return {"success": false, "role": null, "must_change_password": false};
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    String? token = await AuthService.getToken();
    return {
      "Authorization": "Bearer ${token ?? ''}",
      "Content-Type": "application/json",
    };
  }

  Future<Map<String, dynamic>?> uploadJustificatifWeb(PlatformFile file) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/notes/upload-justificatif"),
      );
      
      String? token = await AuthService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final bytes = await file.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        print("Erreur d'upload : ${response.body}");
        return null;
      }
    } catch (e) {
      print("Exception lors de l'upload : $e");
      return null;
    }
  }

  Future<bool> register(String nom, String email, String password, String role) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "nom": nom,
          "email": email,
          "password": password,
          "role": role,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print("Erreur d'inscription : ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception lors de l'inscription : $e");
      return false;
    }
  }

  Future<bool> createExpense({
    required String titre,
    required double montantTtc,
    required double montantTva,
    required String dateDepense,
    String? justificatifUrl,
  }) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/notes/'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'titre': titre,
          'montant_ttc': montantTtc,
          'montant_tva': montantTva,
          'date_depense': dateDepense,
          'justificatif_url': justificatifUrl,
        }),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Erreur createExpense: $e");
      return false;
    }
  }

  Future<List<dynamic>?> getMyExpenses() async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/notes/my-notes'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (e) {
      debugPrint("Erreur lors de la récupération de mes notes : $e");
    }
    return null;
  }

  Future<List<dynamic>?> getPendingExpenses() async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/notes/en-attente'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data;
      }
    } catch (e) {
      debugPrint("Erreur lors de la récupération des notes en attente : $e");
    }
    return null;
  }

  Future<bool> updateNoteStatus(int noteId, String statut, {String? motifRejet}) async {
    try {
      final token = await AuthService.getToken();
      
      var request = http.MultipartRequest('PATCH', Uri.parse('$baseUrl/notes/$noteId/statut'));
      request.fields['statut'] = statut;
      if (motifRejet != null && motifRejet.isNotEmpty) {
        request.fields['motif_rejet'] = motifRejet;
      }
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      var streamedResponse = await request.send();
      return streamedResponse.statusCode == 200;
    } catch (e) {
      debugPrint("Erreur lors de la mise à jour du statut : $e");
      return false;
    }
  }

  Future<List<dynamic>?> getAllExpenses({String? statut}) async {
    String url = '$baseUrl/notes/all';
    if (statut != null) {
      url += '?statut=$statut';
    }

    final token = await AuthService.getToken();
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception("Erreur lors de la récupération des notes de frais");
    }
  }

  Future<bool> deleteExpense(int noteId) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.delete(
        Uri.parse('$baseUrl/notes/$noteId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Erreur suppression note : $e");
      return false;
    }
  }

  Future<bool> cancelExpense(int noteId) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/notes/$noteId/annuler'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Erreur annulation note employé : $e");
      return false;
    }
  }

  Future<bool> resetUserPassword(int userId, String newPassword) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/admin/users/$userId/password'),
        headers: {
          "Authorization": "Bearer ${token ?? ''}",
          "Content-Type": "application/json"
        },
        body: jsonEncode({"password": newPassword}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Erreur reset password : $e");
      return false;
    }
  }

  Future<List<dynamic>> getAllUsers() async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/users'),
        headers: {
          "Authorization": "Bearer ${token ?? ''}",
          "Content-Type": "application/json"
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Erreur lors du chargement des utilisateurs');
      }
    } catch (e) {
      print("Erreur getAllUsers : $e");
      rethrow;
    }
  }

  Future<bool> resetPassword(int userId, String newPassword) async {
    final url = Uri.parse('$baseUrl/admin/users/$userId/password');
    
    try {
      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"password": newPassword}),
      );
      
      print("Code HTTP : ${response.statusCode}");
      print("Réponse du serveur : ${response.body}");
      
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception("Erreur serveur : ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Exception attrapée : $e");
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  Future<bool> changePassword(String newPassword) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/users/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': newPassword}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Erreur changePassword: $e");
      return false;
    }
  }
}