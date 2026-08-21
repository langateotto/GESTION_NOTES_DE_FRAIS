import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../EmployeeTrackingScreen.dart';
import '../login_screen.dart';

class AccountantDashboardScreen extends StatefulWidget {
  final ApiService? apiService;

  const AccountantDashboardScreen({super.key, this.apiService});

  @override
  State<AccountantDashboardScreen> createState() => _AccountantDashboardScreenState();
}

class _AccountantDashboardScreenState extends State<AccountantDashboardScreen> {
  bool _isLoading = true;
  List<dynamic> _pendingExpenses = [];
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  late final ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadPendingExpenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🔍 Fonction sécurisée pour récupérer le nom de l'employé
  String _getEmployeeName(Map<String, dynamic> expense) {
    if (expense['employe_nom'] != null) return expense['employe_nom'].toString();
    if (expense['employee'] != null) return expense['employee'].toString();
    if (expense['user_name'] != null) return expense['user_name'].toString();
    if (expense['nom'] != null) return expense['nom'].toString();
    if (expense['username'] != null) return expense['username'].toString();
    if (expense['prenom'] != null) return expense['prenom'].toString();
    if (expense['name'] != null) return expense['name'].toString();
    
    if (expense['user'] is Map) {
      final userMap = expense['user'] as Map;
      return userMap['nom'] ?? userMap['name'] ?? userMap['username'] ?? userMap['prenom'] ?? 'Employé';
    }
    
    return 'Employé';
  }

  Future<void> _loadPendingExpenses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _apiService.getPendingExpenses();
      setState(() {
        _pendingExpenses = data ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur de chargement : $e")),
        );
      }
    }
  }

  void _logout() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(apiService: _apiService),
      ),
    );
  }

  void _validateExpense(int id, bool approved, {String? motif}) async {
    String statut = approved ? 'valide' : 'rejete';
    bool success = await _apiService.updateNoteStatus(id, statut, motifRejet: motif);

    if (success) {
      setState(() {
        _pendingExpenses.removeWhere((expense) => expense["id"] == id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approved ? "✅ Note de frais approuvée" : "❌ Note de frais rejetée")),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Erreur lors de la mise à jour du statut sur le serveur")),
        );
      }
    }
  }

  Future<void> _deleteExpense(int id) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer la note"),
        content: const Text("Voulez-vous vraiment supprimer définitivement cette note de frais ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      bool success = await _apiService.deleteExpense(id);
      if (success) {
        setState(() {
          _pendingExpenses.removeWhere((expense) => expense["id"] == id);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("🗑️ Note de frais supprimée définitivement")),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ Erreur lors de la suppression sur le serveur")),
          );
        }
      }
    }
  }

  void _showDetailModal(Map<String, dynamic> expense) {
    final TextEditingController motifController = TextEditingController();
    final employeeName = _getEmployeeName(expense);
    
    final String? rawPath = expense['url_fichier'] ?? 
                          expense['justificatif_url'] ?? 
                          expense['imageUrl'] ?? 
                          expense['chemin_fichier'] ?? 
                          expense['file'];
    
    final String fullFileUrl = rawPath != null && rawPath.startsWith('http')
        ? rawPath
        : "${_apiService.baseUrl.replaceAll(RegExp(r'/$'), '')}/${rawPath?.replaceFirst(RegExp(r'^/'), '') ?? ''}";

    final bool isPdf = rawPath != null && rawPath.toLowerCase().endsWith('.pdf');
    final String dateDepense = expense['date_depense'] ?? expense['date'] ?? 'N/A';
    final String? dateSoumission = expense['date_soumission'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Validation - $employeeName"),
        content: SizedBox(
          width: 800,
          height: 600,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: rawPath != null && rawPath.isNotEmpty
                        ? (isPdf
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "Document PDF joint",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final Uri uri = Uri.parse(fullFileUrl);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      } else {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Impossible d'ouvrir le PDF")),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text("Ouvrir le PDF"),
                                  ),
                                ],
                              )
                            : InteractiveViewer(
                                panEnabled: true,
                                boundaryMargin: const EdgeInsets.all(20),
                                minScale: 1.0,
                                maxScale: 4.0,
                                child: Image.network(
                                  fullFileUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Text(
                                    "Impossible de charger l'image du ticket",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ))
                        : const Text("Aucun justificatif joint"),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Titre : ${expense['titre'] ?? expense['category'] ?? 'N/A'}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text("Montant : ${expense['montant_ttc'] ?? expense['amount']} €", style: const TextStyle(fontSize: 22, color: Colors.green, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text("Date d'achat : $dateDepense", style: const TextStyle(fontSize: 15)),
                    if (dateSoumission != null && dateSoumission.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text("Soumis le : $dateSoumission", style: TextStyle(fontSize: 14, color: Colors.grey[700], fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 25),
                    TextField(
                      controller: motifController,
                      decoration: const InputDecoration(
                        labelText: "Motif de refus (obligatoire si rejet)",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                          tooltip: "Supprimer la note",
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteExpense(expense['id']);
                          },
                        ),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: () {
                                if (motifController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Veuillez indiquer un motif de rejet")),
                                  );
                                  return;
                                }
                                Navigator.pop(context);
                                _validateExpense(expense['id'], false, motif: motifController.text);
                              },
                              icon: const Icon(Icons.close),
                              label: const Text("Rejeter"),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              onPressed: () {
                                Navigator.pop(context);
                                _validateExpense(expense['id'], true);
                              },
                              icon: const Icon(Icons.check),
                              label: const Text("Approuver"),
                            ),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filtrage dynamique sécurisé basé sur le nom de l'employé
    final filteredExpenses = _pendingExpenses.where((expense) {
      final employeeName = _getEmployeeName(expense).toLowerCase();
      return employeeName.contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard Comptable - Notes de Frais"),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualiser",
            onPressed: _loadPendingExpenses,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Se déconnecter",
            onPressed: _logout,
          )
        ],
      ),
      body: Row(
        children: [
          Material(
            color: Colors.blueGrey[800],
            child: SizedBox(
              width: 250,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      "Espace Comptable",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.assignment, color: Colors.white),
                    title: const Text("À valider", style: TextStyle(color: Colors.white)),
                    selected: true,
                    selectedTileColor: Colors.blueGrey[700],
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.people, color: Colors.white70),
                    title: const Text("Suivi des Employés", style: TextStyle(color: Colors.white70)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EmployeeTrackingScreen(apiService: _apiService),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Notes de frais en attente de validation",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  
                  // Champ de recherche dynamique instantané
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                      });
                    },
                    decoration: InputDecoration(
                      labelText: "Rechercher par nom d'employé...",
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = "";
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredExpenses.isEmpty
                            ? Center(
                                child: Text(
                                  _pendingExpenses.isEmpty
                                      ? "Aucune note de frais en attente 🎉"
                                      : "Aucun résultat trouvé pour '$_searchQuery'",
                                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                                ),
                              )
                            : Card(
                                elevation: 3,
                                child: ListView.separated(
                                  itemCount: filteredExpenses.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final expense = filteredExpenses[index];
                                    final employeeName = _getEmployeeName(expense);
                                    
                                    final String dateDepense = expense['date_depense'] ?? expense['date'] ?? 'N/A';
                                    final String? dateSoumission = expense['date_soumission'];

                                    String subtitleText = "Date d'achat : $dateDepense";
                                    if (dateSoumission != null && dateSoumission.isNotEmpty) {
                                      subtitleText += " | Soumis le : $dateSoumission";
                                    }

                                    return ListTile(
                                      leading: const CircleAvatar(child: Icon(Icons.receipt)),
                                      title: Text(
                                        "$employeeName - ${expense['titre'] ?? 'Frais'} - ${expense['montant_ttc'] ?? '0'} €",
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(subtitleText),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                                            tooltip: "Supprimer",
                                            onPressed: () => _deleteExpense(expense['id']),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            onPressed: () => _showDetailModal(expense),
                                            icon: const Icon(Icons.search, size: 18),
                                            label: const Text("Vérifier"),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}