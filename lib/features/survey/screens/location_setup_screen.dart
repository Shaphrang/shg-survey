import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'household_entry_screen.dart';

class LocationSetupScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? initialDistricts;

  const LocationSetupScreen({
    super.key,
    this.initialDistricts,
  });

  @override
  State<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

class _LocationSetupScreenState extends State<LocationSetupScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  String? selectedDistrictId;
  String? selectedBlockId;
  String? selectedVillageId;

  List<Map<String, dynamic>> districts = [];
  List<Map<String, dynamic>> blocks = [];
  List<Map<String, dynamic>> villages = [];

  bool loadingDistricts = true;
  bool loadingBlocks = false;
  bool loadingVillages = false;
  bool saving = false;

  String? loadError;

  @override
  void initState() {
    super.initState();

    if (widget.initialDistricts != null && widget.initialDistricts!.isNotEmpty) {
      districts = List<Map<String, dynamic>>.from(widget.initialDistricts!);
      loadingDistricts = false;
    } else {
      loadDistricts();
    }
  }

  Route _noAnimationRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  Future<void> loadDistricts() async {
    setState(() {
      loadingDistricts = true;
      loadError = null;
    });

    try {
      final data = await supabase
          .from('districts')
          .select('id, name')
          .order('name');

      if (!mounted) return;

      setState(() {
        districts = List<Map<String, dynamic>>.from(data);
        loadingDistricts = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingDistricts = false;
        loadError = "Unable to load districts. Please check internet and retry.";
      });

      debugPrint("❌ District load error: $e");
    }
  }

  Future<void> loadBlocks(String districtId) async {
    setState(() {
      loadingBlocks = true;
      selectedBlockId = null;
      selectedVillageId = null;
      blocks = [];
      villages = [];
    });

    try {
      final data = await supabase
          .from('blocks')
          .select('id, name, district_id')
          .eq('district_id', districtId)
          .order('name');

      if (!mounted) return;

      setState(() {
        blocks = List<Map<String, dynamic>>.from(data);
        loadingBlocks = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingBlocks = false;
      });

      showTopSnack(
        "Unable to load blocks. Please try again.",
        isError: true,
      );

      debugPrint("❌ Block load error: $e");
    }
  }

  Future<void> loadVillages(String blockId) async {
    setState(() {
      loadingVillages = true;
      selectedVillageId = null;
      villages = [];
    });

    try {
      final data = await supabase
          .from('villages')
          .select('id, name, block_id, district_id, auth_code')
          .eq('block_id', blockId)
          .order('name');

      if (!mounted) return;

      setState(() {
        villages = List<Map<String, dynamic>>.from(data);
        loadingVillages = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingVillages = false;
      });

      showTopSnack(
        "Unable to load villages. Please try again.",
        isError: true,
      );

      debugPrint("❌ Village load error: $e");
    }
  }

  void clearForm() {
    setState(() {
      selectedDistrictId = null;
      selectedBlockId = null;
      selectedVillageId = null;
      blocks = [];
      villages = [];
    });
  }

  void showTopSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? const Color(0xFFDC2626) : const Color(0xFF0F766E),
      ),
    );
  }

  Future<bool> showAuthDialog(String correctCode) async {
    final TextEditingController codeController = TextEditingController();
    bool obscure = true;
    String? errorText;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return Dialog(
                  insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          gradient: LinearGradient(
                            colors: [Color(0xFF0F6FFF), Color(0xFF38D39F)],
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Authentication Required",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Text(
                              "Enter the village authentication code to continue.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: codeController,
                              autofocus: true,
                              obscureText: obscure,
                              decoration: InputDecoration(
                                labelText: "Authentication Code",
                                hintText: "Enter code",
                                errorText: errorText,
                                prefixIcon: const Icon(Icons.verified_user),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setDialogState(() {
                                      obscure = !obscure;
                                    });
                                  },
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text("Cancel"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (codeController.text.trim() ==
                                          correctCode.trim()) {
                                        Navigator.pop(dialogContext, true);
                                      } else {
                                        setDialogState(() {
                                          errorText =
                                              "Incorrect authentication code";
                                        });
                                      }
                                    },
                                    child: const Text("Submit"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ) ??
        false;
  }

  Future<void> onContinue() async {
    if (saving) return;

    if (selectedDistrictId == null ||
        selectedBlockId == null ||
        selectedVillageId == null) {
      showTopSnack(
        "Please select district, block and village",
        isError: true,
      );
      return;
    }

    final selectedVillage =
        villages.firstWhere((v) => v['id'] == selectedVillageId);

    final correctCode = (selectedVillage['auth_code'] ?? '').toString();

    if (correctCode.isEmpty) {
      showTopSnack(
        "Authentication code not found for selected village",
        isError: true,
      );
      return;
    }

    final isVerified = await showAuthDialog(correctCode);
    if (!isVerified) return;

    setState(() {
      saving = true;
    });

    try {
      final box = Hive.box('session_box');

      await box.put('survey_session', {
        "district_id": selectedDistrictId,
        "block_id": selectedBlockId,
        "village_id": selectedVillageId,
        "district_name": districts
            .firstWhere((d) => d['id'] == selectedDistrictId)['name'],
        "block_name":
            blocks.firstWhere((b) => b['id'] == selectedBlockId)['name'],
        "village_name": selectedVillage['name'],
        "auth_verified": true,
        "saved_at": DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        _noAnimationRoute(const HouseholdEntryScreen()),
      );
    } catch (e) {
      debugPrint("❌ Save session error: $e");

      if (!mounted) return;

      showTopSnack(
        "Failed to save session locally",
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loadingDistricts) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F6FFF),
                Color(0xFF2F80ED),
                Color(0xFF38D39F),
              ],
            ),
          ),
          child: const SafeArea(
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    if (loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Survey Setup")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 42,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF334155),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: loadDistricts,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Retry"),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 16,
      title: const Text(
        "MSRLS - Household Survey",
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
          letterSpacing: 0.2,
        ),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFF0F172A),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: IconButton(
            tooltip: "Clear All Data",
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: const BorderSide(
                color: Color(0xFFE2E8F0),
              ),
            ),
            icon: const Icon(
              Icons.delete_sweep_rounded,
              size: 22,
              color: Color(0xFFDC2626),
            ),
            onPressed: clearForm,
          ),
        ),
      ],
    ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F6FFF), Color(0xFF38D39F)],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 6),
                Text(
                  "Select Survey Location",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "This will be asked only once. After verification, the location is saved locally and next time the app opens it will directly continue to household entry.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(
                  title: "Location Details",
                  subtitle: "Data is loaded live from Supabase",
                  child: Column(
                    children: [
                      _buildDropdown(
                        label: "District",
                        hint: "Select district",
                        icon: Icons.location_city_rounded,
                        value: districts.any((e) => e['id'] == selectedDistrictId)
                            ? selectedDistrictId
                            : null,
                        items: districts,
                        onChanged: (v) async {
                          if (v == null) return;

                          setState(() {
                            selectedDistrictId = v;
                            selectedBlockId = null;
                            selectedVillageId = null;
                            blocks = [];
                            villages = [];
                          });

                          await loadBlocks(v);
                        },
                      ),
                      if (loadingBlocks)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      const SizedBox(height: 14),
                      _buildDropdown(
                        label: "Block",
                        hint: "Select block",
                        icon: Icons.map_rounded,
                        value: blocks.any((e) => e['id'] == selectedBlockId)
                            ? selectedBlockId
                            : null,
                        items: blocks,
                        onChanged: (v) async {
                          if (v == null) return;

                          setState(() {
                            selectedBlockId = v;
                            selectedVillageId = null;
                            villages = [];
                          });

                          await loadVillages(v);
                        },
                      ),
                      if (loadingVillages)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      const SizedBox(height: 14),
                      _buildDropdown(
                        label: "Village",
                        hint: "Select village",
                        icon: Icons.home_work_rounded,
                        value: villages.any((e) => e['id'] == selectedVillageId)
                            ? selectedVillageId
                            : null,
                        items: villages,
                        onChanged: (v) {
                          setState(() {
                            selectedVillageId = v;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_rounded, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Authentication code is fetched from the selected village and will be asked only after you press Continue.",
                          style: TextStyle(
                            color: Color(0xFF1E3A8A),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F6FFF), Color(0xFF38D39F)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F6FFF).withOpacity(0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: saving ? null : onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    child: saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Continue",
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String hint,
    required IconData icon,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e['id'].toString(),
              child: Text((e['name'] ?? '').toString()),
            ),
          )
          .toList(),
      onChanged: items.isEmpty ? null : onChanged,
    );
  }
}