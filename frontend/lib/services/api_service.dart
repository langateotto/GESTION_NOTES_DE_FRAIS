import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
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
        print("👤 [LOGIN] Rôle détecté : $role");

        await AuthService.saveUserSession(token, role);

        return {"success": true, "role": role};
      } else {
        print("❌ [LOGIN] Échec de la connexion.");
        return {"success": false, "role": null};
      }
    } catch (e) {
      print("🔥 [LOGIN] Erreur de connexion : $e");
      return {"success": false, "role": null};
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

      // Gestion universelle bytes (Web/Mobile) ou path (Mobile)
      if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else if (file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ),
        );
      } else {
        print("Erreur d'upload : Aucun contenu trouvé pour le fichier.");
        return null;
      }

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

  // ==================== AJOUTÉ : Création définitive de la note de frais ====================
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
        Uri.parse('$baseUrl/notes/'), // Adaptez l'endpoint si besoin selon votre FastAPI (ex: /notes ou /notes/create)
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

  // ==================== AJOUTÉ : Récupérer ses propres notes (Suivi employé) ====================
  Future<List<dynamic>?> getMyExpenses() async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/notes/my-notes'), // Adaptez l'endpoint selon votre route backend
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
}