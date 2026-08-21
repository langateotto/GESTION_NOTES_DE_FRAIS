import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class EmployeeTrackingScreen extends StatefulWidget {
  final ApiService apiService;

  const EmployeeTrackingScreen({super.key, required this.apiService});

  @override
  State<EmployeeTrackingScreen> createState() => _EmployeeTrackingScreenState();
}

class _EmployeeTrackingScreenState extends State<EmployeeTrackingScreen> {
  bool _isLoading = true;
  List<dynamic> _employeesExpenses = [];
  String? _selectedStatutFilter;

  @override
  void initState() {
    super.initState();
    _loadAllExpenses();
  }

  Future<void> _loadAllExpenses() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.apiService.getAllExpenses(statut: _selectedStatutFilter); 
      setState(() {
        _employeesExpenses = data ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur de chargement : $e")),
        );
      }
    }
  }

  Future<void> _updateNoteStatus(int noteId, String nouveauStatut, {String? motif}) async {
    try {
      await widget.apiService.updateNoteStatus(noteId, nouveauStatut, motifRejet: motif);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Statut mis à jour avec succès (${nouveauStatut.toUpperCase()})")),
        );
      }
      _loadAllExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur : $e")),
        );
      }
    }
  }

  // Suppression définitive (Hard Delete) par le comptable
  Future<void> _deleteExpense(int noteId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Suppression définitive"),
        content: const Text("Voulez-vous vraiment supprimer définitivement cette note de la base de données ? Cette action est irréversible."),
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
    ) ?? false;

    if (confirm) {
      try {
        bool success = await widget.apiService.deleteExpense(noteId);
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("🗑️ Note supprimée définitivement")),
            );
          }
          _loadAllExpenses();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("❌ Erreur lors de la suppression")),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Erreur : $e")),
          );
        }
      }
    }
  }

  // Cherche explicitement 'nom_user' (basé sur votre table SQL)
  String _getEmployeeName(Map<String, dynamic> expense) {
    if (expense['nom_user'] != null) return expense['nom_user'].toString();
    if (expense['employe_nom'] != null) return expense['employe_nom'].toString();
    if (expense['user_name'] != null) return expense['user_name'].toString();
    
    if (expense['utilisateur'] is Map) {
      return expense['utilisateur']['nom_user'] ?? 'Employé';
    }
    if (expense['user'] is Map) {
      return expense['user']['nom_user'] ?? 'Employé';
    }
    
    return 'Employé #${expense['utilisateur_id'] ?? ''}';
  }

  void _showActionDialog(Map<String, dynamic> expense, String currentStatus) {
    final noteId = expense['id'];
    final titre = expense['titre'] ?? expense['description'] ?? 'Frais';
    final employe = _getEmployeeName(expense);
    final TextEditingController motifController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Gérer la note : $titre"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Employé : $employe"),
            Text("Montant : ${expense['montant_ttc']} €"),
            Text("Statut actuel : ${currentStatus.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (currentStatus != 'annule') ...[
              TextField(
                controller: motifController,
                decoration: const InputDecoration(
                  labelText: "Motif (obligatoire en cas de rejet)",
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              const Text(
                "Cette note a été annulée par l'employé. Vous pouvez la supprimer définitivement.",
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              )
            ],
          ],
        ),
        actions: [
          // Bouton pour supprimer définitivement de la BDD
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteExpense(noteId);
            },
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
          const Spacer(), // Pousse les autres boutons vers la droite
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fermer"),
          ),
          // N'afficher Rejeter / Valider que si la note n'est pas déjà annulée
          if (currentStatus != 'annule') ...[
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                if (motifController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Veuillez indiquer un motif de rejet")),
                  );
                  return;
                }
                Navigator.pop(context);
                _updateNoteStatus(noteId, 'rejete', motif: motifController.text);
              },
              child: const Text("Rejeter"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _updateNoteStatus(noteId, 'valide');
              },
              child: const Text("Valider"),
            ),
          ]
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Suivi des notes de frais par employé"),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Historique global et suivi",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text("Toutes"),
                    selected: _selectedStatutFilter == null,
                    onSelected: (selected) {
                      setState(() => _selectedStatutFilter = null);
                      _loadAllExpenses();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text("En attente"),
                    selected: _selectedStatutFilter == 'en_attente',
                    onSelected: (selected) {
                      setState(() => _selectedStatutFilter = 'en_attente');
                      _loadAllExpenses();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text("Validées"),
                    selected: _selectedStatutFilter == 'valide',
                    onSelected: (selected) {
                      setState(() => _selectedStatutFilter = 'valide');
                      _loadAllExpenses();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text("Rejetées"),
                    selected: _selectedStatutFilter == 'rejete',
                    onSelected: (selected) {
                      setState(() => _selectedStatutFilter = 'rejete');
                      _loadAllExpenses();
                    },
                  ),
                  const SizedBox(width: 8),
                  // Ajout du filtre pour les notes annulées
                  ChoiceChip(
                    label: const Text("Annulées"),
                    selected: _selectedStatutFilter == 'annule',
                    selectedColor: Colors.grey[300],
                    onSelected: (selected) {
                      setState(() => _selectedStatutFilter = 'annule');
                      _loadAllExpenses();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _employeesExpenses.isEmpty
                      ? const Center(child: Text("Aucune note de frais trouvée."))
                      : ListView.builder(
                          itemCount: _employeesExpenses.length,
                          itemBuilder: (context, index) {
                            final expense = _employeesExpenses[index];
                            final status = expense['statut'] ?? 'en_attente';
                            final employeNom = _getEmployeeName(expense);
                            final titreFrais = expense['titre'] ?? expense['description'] ?? 'Frais';
                            
                            // Détermination de la couleur selon le statut
                            Color statusColor = Colors.orange;
                            if (status == 'valide') statusColor = Colors.green;
                            if (status == 'rejete') statusColor = Colors.red;
                            if (status == 'annule') statusColor = Colors.grey;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                onTap: () => _showActionDialog(expense, status),
                                leading: CircleAvatar(
                                  backgroundColor: statusColor.withValues(alpha: 0.2),
                                  child: Icon(
                                    status == 'annule' ? Icons.block : Icons.person, 
                                    color: statusColor
                                  ),
                                ),
                                title: Text(
                                  "$employeNom - $titreFrais",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    // Barrer le texte si la note est annulée
                                    decoration: status == 'annule' ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                subtitle: Text(
                                  "Montant : ${expense['montant_ttc']} € | Date : ${expense['date_depense'] ?? 'N/A'}",
                                ),
                                trailing: Chip(
                                  label: Text(
                                    status.toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  backgroundColor: statusColor,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}