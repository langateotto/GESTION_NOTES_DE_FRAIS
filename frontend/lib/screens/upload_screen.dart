import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class UploadScreen extends StatefulWidget {
  final ApiService apiService;

  const UploadScreen({super.key, required this.apiService});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  PlatformFile? _selectedFile;
  bool _isLoading = false;
  
  final TextEditingController _montantTtcController = TextEditingController();
  final TextEditingController _montantTvaController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _titreController = TextEditingController();

  String? _justificatifUrl;

  // Méthode pour tout réinitialiser
  void _resetForm() {
    setState(() {
      _selectedFile = null;
      _titreController.clear();
      _montantTtcController.clear();
      _montantTvaController.clear();
      _dateController.clear();
      _justificatifUrl = null;
    });
  }

  // Méthode pour choisir un fichier (Image ou PDF)
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true, // Indispensable pour récupérer les bytes sur toutes les plateformes
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFile = result.files.single;
        });
        await _uploadAndAnalyze();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur lors de la sélection du fichier : $e")),
        );
      }
    }
  }

  Future<void> _uploadAndAnalyze() async {
    if (_selectedFile == null) return;

    setState(() {
      _isLoading = true;
    });

    dynamic result;
    try {
      // Correction ici : on appelle la bonne méthode selon la plateforme ou une méthode unifiée gérant les bytes
      if (kIsWeb) {
        result = await widget.apiService.uploadJustificatifWeb(_selectedFile!);
      } else {
        // Si vous avez une méthode dédiée mobile, utilisez-la, sinon l'envoi par bytes fonctionne généralement aussi
        result = await widget.apiService.uploadJustificatifWeb(_selectedFile!);
      }
    } catch (e) {
      print("Erreur upload API : $e");
    }

    setState(() {
      _isLoading = false;
    });

    // Adaptation selon la structure renvoyée par votre backend Python (nouvelle_note ou note_creee)
    final noteData = result?["note_creee"] ?? result;

    if (result != null && (noteData != null || result["note_id"] != null)) {
      setState(() {
        _montantTtcController.text = noteData["montant_ttc"]?.toString() ?? "0.0";
        _montantTvaController.text = noteData["montant_tva"]?.toString() ?? "0.0";
        _dateController.text = noteData["date_depense"] ?? "";
        _titreController.text = noteData["titre"] ?? "";
        _justificatifUrl = noteData["justificatif_url"];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Justificatif analysé et enregistré avec succès !")),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Erreur lors de l'analyse du justificatif par l'IA.")),
        );
      }
    }
  }

  bool _isPdf(String? path) {
    if (path == null) return false;
    return path.toLowerCase().endsWith('.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final bool isPdfFile = _isPdf(_selectedFile?.name);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nouvelle Note de Frais"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Réinitialiser / Nouveau fichier",
            onPressed: _resetForm,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Se déconnecter",
            onPressed: () async {
              await AuthService.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoginScreen(apiService: widget.apiService),
                  ),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: _selectedFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: isPdfFile
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Text(
                                    _selectedFile!.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Text("Document PDF sélectionné", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            )
                          : (kIsWeb
                              ? (_selectedFile!.bytes != null
                                  ? Image.memory(_selectedFile!.bytes!, fit: BoxFit.cover)
                                  : const Center(child: Text("Aperçu indisponible")))
                              : Image.file(File(_selectedFile!.path!), fit: BoxFit.cover)),
                    )
                  : const Center(
                      child: Text("Aucun justificatif sélectionné (PDF, JPG, PNG)",
                          style: TextStyle(color: Colors.grey)),
                    ),
            ),
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text("Sélectionner un justificatif (PDF ou Image)"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            
            const SizedBox(height: 24),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              TextField(
                controller: _titreController,
                decoration: const InputDecoration(labelText: "Titre / Description"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _montantTtcController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Montant TTC (€)"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _montantTvaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Montant TVA (€)"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dateController,
                decoration: const InputDecoration(labelText: "Date de dépense (AAAA-MM-JJ)"),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Note validée et transmise au comptable !")),
                  );
                  _resetForm();
                },
                child: const Text("Soumettre au Comptable", style: TextStyle(fontSize: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}