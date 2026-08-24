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
  bool _isHistoryLoading = false;
  List<dynamic> _myExpenses = [];

  final TextEditingController _montantTtcController = TextEditingController();
  final TextEditingController _montantTvaController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _titreController = TextEditingController();

  String? _justificatifUrl;

  @override
  void initState() {
    super.initState();
    _fetchMyExpenses();
  }

  // Récupérer les notes de frais de l'employé connecté
  Future<void> _fetchMyExpenses() async {
    setState(() => _isHistoryLoading = true);
    try {
      final data = await widget.apiService.getMyExpenses();
      setState(() {
        _myExpenses = data ?? [];
        _isHistoryLoading = false;
      });
    } catch (e) {
      setState(() => _isHistoryLoading = false);
    }
  }

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

Future<void> _pickFile() async {
  try {
    // Utilisation directe de pickFile() pour un fichier unique
    PlatformFile? result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = result;
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

    setState(() => _isLoading = true);

    dynamic result;
    try {
      result = await widget.apiService.uploadJustificatifWeb(_selectedFile!);
      print("📦 [UPLOAD RESULT] : $result");
    } catch (e) {
      print("Erreur upload API : $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (result != null) {
      final data = result["note_creee"] ?? result["data"] ?? result;

      setState(() {
        var montantTtcVal = data["montant_ttc"] ?? data["montant"] ?? data["total"];
        if (montantTtcVal != null && montantTtcVal != 0 && montantTtcVal != 0.0) {
          _montantTtcController.text = montantTtcVal.toString();
        }

        var montantTvaVal = data["montant_tva"] ?? data["tva"];
        if (montantTvaVal != null && montantTvaVal != 0 && montantTvaVal != 0.0) {
          _montantTvaController.text = montantTvaVal.toString();
        }

        _titreController.text = data["titre"] ?? data["description"] ?? "Note de frais - ${_selectedFile?.name ?? ''}";
        _dateController.text = data["date_depense"] ?? data["date"] ?? "";
        _justificatifUrl = data["justificatif_url"] ?? data["url"];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⏳ Upload reçu. Vérifiez ou ajustez les montants si besoin."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _fetchMyExpenses();
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Erreur lors de l'envoi du justificatif.")),
        );
      }
    }
  }

  // Soumission définitive de la note de frais
  Future<void> _submitExpense() async {
    if (_titreController.text.isEmpty || _montantTtcController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez remplir les champs obligatoires")),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      bool success = await widget.apiService.createExpense(
        titre: _titreController.text,
        montantTtc: double.tryParse(_montantTtcController.text.replaceAll(',', '.')) ?? 0.0,
        montantTva: double.tryParse(_montantTvaController.text.replaceAll(',', '.')) ?? 0.0,
        dateDepense: _dateController.text,
        justificatifUrl: _justificatifUrl,
      );

      setState(() => _isLoading = false);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Note soumise au comptable avec succès !")),
          );
        }
        _resetForm();
        _fetchMyExpenses();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ Erreur lors de l'enregistrement de la note.")),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur : $e")),
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Espace Employé - Notes de Frais"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_circle), text: "Nouvelle Note"),
              Tab(icon: Icon(Icons.list_alt), text: "Mon Suivi"),
            ],
          ),
          actions: [
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
        body: TabBarView(
          children: [
            // ONGLET 1 : Création / Upload
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 180,
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
                                      const Icon(Icons.picture_as_pdf, size: 50, color: Colors.red),
                                      const SizedBox(height: 8),
                                      Text(_selectedFile!.name, textAlign: TextAlign.center),
                                    ],
                                  )
                                : (kIsWeb
                                    ? FutureBuilder<Uint8List>(
                                        future: _selectedFile!.readAsBytes(),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.done &&
                                              snapshot.hasData) {
                                            return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                          }
                                          return const Center(child: CircularProgressIndicator());
                                        },
                                      )
                                    : Image.file(File(_selectedFile!.path!), fit: BoxFit.cover)),
                          )
                        : const Center(
                            child: Text("Aucun justificatif sélectionné", style: TextStyle(color: Colors.grey)),
                          ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text("Sélectionner un justificatif (PDF/Image)"),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    TextField(
                      controller: _titreController,
                      decoration: const InputDecoration(labelText: "Titre / Description", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _montantTtcController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Montant TTC (€)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _montantTvaController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Montant TVA (€)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _dateController,
                      decoration: const InputDecoration(labelText: "Date (AAAA-MM-JJ)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _submitExpense,
                      child: const Text("Soumettre au Comptable", style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ],
              ),
            ),

            // ONGLET 2 : Suivi des notes de l'employé
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isHistoryLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _fetchMyExpenses,
                      child: _myExpenses.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.6,
                                  child: const Center(
                                    child: Text("Vous n'avez soumis aucune note de frais."),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _myExpenses.length,
                              itemBuilder: (context, index) {
                                final note = _myExpenses[index];
                                final status = note['statut'] ?? 'en_attente';
                                final dateDepense = note['date_depense'] ?? 'N/A';
                                final dateSoumission = note['date_soumission'];

                                Color statusColor = Colors.orange;
                                if (status == 'valide') statusColor = Colors.green;
                                if (status == 'rejete' || status == 'annule') statusColor = Colors.red;

                                String subtitleText = "Montant : ${note['montant_ttc']} €\nDate d'achat : $dateDepense";
                                if (dateSoumission != null) {
                                  subtitleText += "\nSoumis le : $dateSoumission";
                                }

                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  child: ListTile(
                                    title: Text(
                                      note['titre'] ?? note['description'] ?? 'Frais',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(subtitleText),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Chip(
                                          label: Text(
                                            status.toUpperCase(),
                                            style: const TextStyle(color: Colors.white, fontSize: 11),
                                          ),
                                          backgroundColor: statusColor,
                                        ),
                                        if (status == 'en_attente') ...[
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                            tooltip: "Annuler la note",
                                            onPressed: () async {
                                              bool? confirm = await showDialog(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  title: const Text("Annuler la note"),
                                                  content: const Text("Voulez-vous vraiment annuler cette demande de remboursement ?"),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, false),
                                                      child: const Text("Non"),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context, true),
                                                      child: const Text("Oui, annuler", style: TextStyle(color: Colors.red)),
                                                    ),
                                                  ],
                                                ),
                                              );

                                              if (confirm == true) {
                                                bool success = await widget.apiService.cancelExpense(note['id']);
                                                if (success) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text("🚫 Note annulée avec succès")),
                                                    );
                                                  }
                                                  _fetchMyExpenses();
                                                } else {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text("❌ Erreur lors de l'annulation")),
                                                    );
                                                  }
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}