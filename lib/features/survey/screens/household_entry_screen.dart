import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/offline_survey_service.dart';
import '../../../core/services/sync_service.dart';
import '../remote/household_remote_service.dart';
import 'location_setup_screen.dart';

class HouseholdEntryScreen extends StatefulWidget {
  const HouseholdEntryScreen({super.key});

  @override
  State<HouseholdEntryScreen> createState() => _HouseholdEntryScreenState();
}

class _HouseholdEntryScreenState extends State<HouseholdEntryScreen> {
  final Box sessionBox = Hive.box('session_box');
  final OfflineSurveyService offlineService = OfflineSurveyService();
  final SyncService syncService = SyncService();
  final HouseholdRemoteService remoteService = HouseholdRemoteService();
  final InternetConnection internetConnection = InternetConnection();
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<InternetStatus>? internetSubscription;
  final Random random = Random();

  Map<String, dynamic> session = {};

  bool isOnline = false;
  bool isCheckingStatus = true;
  bool isSaving = false;
  bool isSyncing = false;
  int pendingCount = 0;
  String? lastConnectionMessage;

  final TextEditingController hofNameController = TextEditingController();
  final TextEditingController hofGuardianSpecifyController =
      TextEditingController();
  final TextEditingController hofAgeController = TextEditingController();
  final TextEditingController hofShgController = TextEditingController();
  final TextEditingController hofAadhaarController = TextEditingController();
  final TextEditingController hofEpicController = TextEditingController();

  String? hofType;
  String? hofGender;
  String? hofMaritalStatus;
  bool hofIsShgMember = false;
  bool hofIsJobCardHolder = false;
  bool hofHasAadhaar = false;
  bool hofHasEpic = false;
  bool hofIsSpecialGroup = false;
  String? hofSpecialGroup;

  final List<Map<String, dynamic>> members = [];

  static const List<String> maritalOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Divorced',
  ];

  static const List<String> specialGroupOptions = [
    'Elderly',
    'PWD',
    'Adolescent Group',
  ];

  @override
  void initState() {
    super.initState();
    final rawSession = sessionBox.get('survey_session');
    if (rawSession is Map) {
      session = Map<String, dynamic>.from(rawSession);
    }
    bootstrap();
  }

  @override
  void dispose() {
    internetSubscription?.cancel();

    hofNameController.dispose();
    hofGuardianSpecifyController.dispose();
    hofAgeController.dispose();
    hofShgController.dispose();
    hofAadhaarController.dispose();
    hofEpicController.dispose();

    super.dispose();
  }

  Future<void> bootstrap() async {
    await refreshPendingCount();
    await refreshConnectionState(showSnack: false);

    internetSubscription =
        internetConnection.onStatusChange.listen((InternetStatus _) async {
      await refreshConnectionState(showSnack: false);
    });
  }

  Future<void> refreshPendingCount() async {
    final count = offlineService.getPendingCount();
    if (!mounted) return;

    setState(() {
      pendingCount = count;
    });
  }

  Future<bool> refreshConnectionState({bool showSnack = false}) async {
    bool reachable = false;
    String? message;

    try {
      await supabase
          .from('districts')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 8));

      reachable = true;
      message = 'Server reachable';
    } catch (e) {
      reachable = false;
      message = readableError(e);
    }

    if (!mounted) return reachable;

    setState(() {
      isOnline = reachable;
      isCheckingStatus = false;
      lastConnectionMessage = message;
    });

    if (showSnack) {
      showAppSnack(
        reachable ? 'Connected to server' : 'Server not reachable: $message',
        isError: !reachable,
      );
    }

    return reachable;
  }

  String readableError(Object error) {
    final raw = error.toString();

    if (raw.contains('SocketException')) {
      return 'No internet connection';
    }
    if (raw.contains('TimeoutException')) {
      return 'Connection timed out';
    }
    if (raw.contains('PostgrestException')) {
      return raw.replaceAll('Exception: ', '');
    }

    return raw.replaceAll('Exception: ', '');
  }

  String generateRef(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(99999)}';
  }

  int? parseAge(String text) {
    return int.tryParse(text.trim());
  }

  bool specialGroupIsPwd(String? value) {
    return value == 'PWD';
  }

  String? validateHof() {
    if (hofNameController.text.trim().isEmpty) {
      return 'Please enter head of family name';
    }
    if (hofType == null) {
      return 'Please select HOF type';
    }
    if (hofType == 'guardian' &&
        hofGuardianSpecifyController.text.trim().isEmpty) {
      return 'Please specify guardian';
    }
    if (hofGender == null) {
      return 'Please select gender';
    }
    if (hofType == 'father' && hofGender != 'M') {
      return 'If HOF type is father, gender must be Male';
    }
    if (hofType == 'mother' && hofGender != 'F') {
      return 'If HOF type is mother, gender must be Female';
    }

    final age = parseAge(hofAgeController.text);
    if (age == null || age < 0 || age > 130) {
      return 'Please enter valid age';
    }

    if (hofMaritalStatus == null) {
      return 'Please select marital status';
    }

    if (hofIsShgMember && hofShgController.text.trim().isEmpty) {
      return 'Please enter SHG name or code';
    }

    if (hofIsSpecialGroup && hofSpecialGroup == null) {
      return 'Please select the special group type';
    }

    if (hofHasAadhaar &&
        !RegExp(r'^\d{12}$').hasMatch(hofAadhaarController.text.trim())) {
      return 'Aadhaar must be 12 digits';
    }

    if (hofHasEpic && hofEpicController.text.trim().isEmpty) {
      return 'Please enter EPIC number';
    }

    return null;
  }

  Future<void> openMemberSheet({
    Map<String, dynamic>? existingMember,
    int? index,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => MemberFormSheet(
        initialMember: existingMember,
      ),
    );

    if (result == null) return;

    final prepared = Map<String, dynamic>.from(result);
    prepared['device_member_ref'] ??= generateRef('mem');

    setState(() {
      if (index != null) {
        members[index] = prepared;
      } else {
        members.add(prepared);
      }
    });
  }

  Future<void> saveHousehold() async {
    if (isSaving) return;

    final validationError = validateHof();
    if (validationError != null) {
      showAppSnack(validationError, isError: true);
      return;
    }

    final canReachServer = await refreshConnectionState(showSnack: false);
    final deviceHouseholdRef = generateRef('hh');

    final householdPayload = <String, dynamic>{
      "device_household_ref": deviceHouseholdRef,
      "district_id": session["district_id"],
      "block_id": session["block_id"],
      "village_id": session["village_id"],
      "hof_name": hofNameController.text.trim(),
      "hof_type": hofType,
      "guardian_specify": hofType == 'guardian'
          ? hofGuardianSpecifyController.text.trim()
          : null,
    };

    final allMembers = <Map<String, dynamic>>[
      {
        "device_member_ref": generateRef('mem'),
        "sort_order": 1,
        "relationship_to_hof": "head_of_family",
        "member_name": hofNameController.text.trim(),
        "gender": hofGender,
        "age": parseAge(hofAgeController.text),
        "marital_status": hofMaritalStatus,
        "is_shg_member": hofIsShgMember,
        "shg_name_or_code":
            hofIsShgMember ? hofShgController.text.trim() : null,
        "special_group": hofIsSpecialGroup ? hofSpecialGroup : null,
        "is_job_card_holder": hofIsJobCardHolder,
        "is_pwd": specialGroupIsPwd(hofSpecialGroup),
        "has_aadhaar": hofHasAadhaar,
        "aadhaar_no": hofHasAadhaar ? hofAadhaarController.text.trim() : null,
        "has_epic": hofHasEpic,
        "epic_no": hofHasEpic ? hofEpicController.text.trim() : null,
      },
      ...members.asMap().entries.map((entry) {
        final i = entry.key;
        final member = Map<String, dynamic>.from(entry.value);

        return {
          ...member,
          "sort_order": i + 2,
        };
      }),
    ];

    setState(() {
      isSaving = true;
    });

    bool savedOnline = false;
    bool savedOffline = false;
    String? remoteError;

    try {
      if (canReachServer) {
        await remoteService
            .saveHouseholdSurvey(
              household: householdPayload,
              members: allMembers,
            )
            .timeout(const Duration(seconds: 15));

        savedOnline = true;
      } else {
        await offlineService.saveHouseholdSurvey(
          household: householdPayload,
          members: allMembers,
        );
        savedOffline = true;
      }
    } catch (e) {
      remoteError = readableError(e);

      await offlineService.saveHouseholdSurvey(
        household: householdPayload,
        members: allMembers,
      );
      savedOffline = true;
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }

    await refreshPendingCount();
    await refreshConnectionState(showSnack: false);
    clearForm();

    if (!mounted) return;

    if (savedOnline) {
      showAppSnack('Household saved to server');
    } else if (savedOffline) {
      showAppSnack(
        remoteError == null
            ? 'Saved offline. Sync later from the banner or menu.'
            : 'Server save failed: $remoteError. Saved offline instead.',
        isError: false,
      );
    }
  }

  Future<void> syncPending() async {
    if (isSyncing || pendingCount == 0) return;

    final canReachServer = await refreshConnectionState(showSnack: false);
    if (!canReachServer) {
      showAppSnack(
        'Server not reachable. Pending households remain offline.',
        isError: true,
      );
      return;
    }

    setState(() {
      isSyncing = true;
    });

    try {
      final result = await syncService.syncAll();
      await refreshPendingCount();
      await refreshConnectionState(showSnack: false);

      if (!mounted) return;

      final uploaded = result["uploaded"] ?? 0;
      final failed = result["failed"] ?? 0;

      if (failed == 0) {
        showAppSnack('$uploaded household(s) synced successfully');
      } else {
        showAppSnack(
          '$uploaded synced, $failed failed.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;

      showAppSnack(
        'Sync failed: ${readableError(e)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
        });
      }
    }
  }

  Future<void> confirmClearAll() async {
    final shouldClear = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Clear all entered data?'),
            content: const Text(
              'This will clear the current household form and all added members from the screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear All'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldClear) return;

    clearForm();
    showAppSnack('Form cleared');
  }

  void clearForm() {
    setState(() {
      hofNameController.clear();
      hofGuardianSpecifyController.clear();
      hofAgeController.clear();
      hofShgController.clear();
      hofAadhaarController.clear();
      hofEpicController.clear();

      hofType = null;
      hofGender = null;
      hofMaritalStatus = null;
      hofIsShgMember = false;
      hofIsJobCardHolder = false;
      hofHasAadhaar = false;
      hofHasEpic = false;
      hofIsSpecialGroup = false;
      hofSpecialGroup = null;

      members.clear();
    });
  }

  void showAppSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            isError ? const Color(0xFFDC2626) : const Color(0xFF0F766E),
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ),
    );
  }

  Future<void> resetLocation() async {
    await sessionBox.delete('survey_session');
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationSetupScreen(),
      ),
      (route) => false,
    );
  }

  String get saveButtonLabel {
    if (isSaving) {
      return isOnline ? 'Saving Household...' : 'Saving Offline...';
    }
    return isOnline ? 'Save Household' : 'Save Offline';
  }

  String get saveButtonSubtitle {
    return isOnline
        ? 'Direct save to Supabase'
        : 'Stored locally and queued for sync';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      drawer: buildAppDrawer(),
      appBar: AppBar(
        title: const Text("Household Entry"),
        actions: [
          IconButton(
            tooltip: "Clear All",
            onPressed: confirmClearAll,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.22),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: isSaving ? null : saveHousehold,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            icon: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                : const Icon(Icons.save_alt_rounded, color: Colors.white),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  saveButtonLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  saveButtonSubtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (pendingCount > 0) buildPendingBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
              children: [
                buildHeaderCard(),
                const SizedBox(height: 18),
                buildHofCard(),
                const SizedBox(height: 18),
                buildMembersCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAppDrawer() {
    final pendingText = pendingCount == 1
        ? '1 household pending'
        : '$pendingCount households pending';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F6FFF), Color(0xFF38D39F)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0x33FFFFFF),
                    child: Icon(
                      Icons.menu_rounded,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Survey Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Manage sync and location actions',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Sync offline households'),
              subtitle: Text(pendingText),
              trailing: isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () async {
                Navigator.pop(context);
                await syncPending();
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Change location'),
              subtitle: const Text('Go back to setup screen'),
              onTap: () async {
                Navigator.pop(context);
                await resetLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPendingBanner() {
    final title = pendingCount == 1
        ? '1 household pending sync'
        : '$pendingCount households pending sync';

    final subtitle = isOnline
        ? 'Tap Sync to upload now'
        : 'Offline now, but you can still try Sync';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.16),
            child: const Icon(
              Icons.cloud_upload_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: isSyncing ? null : syncPending,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withOpacity(0.14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : const Text(
                    "Sync",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }


Widget buildHeaderCard() {
  final district = (session["district_name"] ?? "-").toString();
  final block = (session["block_name"] ?? "-").toString();
  final village = (session["village_name"] ?? "-").toString();

  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF2563EB).withOpacity(0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8FBFF),
              Color(0xFFEEF6FF),
              Color(0xFFF4FFFC),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFBFDBFE).withOpacity(0.55),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -35,
              right: -20,
              child: _buildSoftGlow(
                size: 130,
                colors: [
                  const Color(0xFF60A5FA).withOpacity(0.20),
                  const Color(0xFF93C5FD).withOpacity(0.10),
                  Colors.transparent,
                ],
              ),
            ),
            Positioned(
              bottom: -45,
              left: -20,
              child: _buildSoftGlow(
                size: 120,
                colors: [
                  const Color(0xFF34D399).withOpacity(0.16),
                  const Color(0xFFA7F3D0).withOpacity(0.08),
                  Colors.transparent,
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.36),
                      Colors.white.withOpacity(0.00),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2563EB),
                              Color(0xFF14B8A6),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withOpacity(0.16),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.home_work_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Household Survey",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.15,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Location details",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF475569).withOpacity(0.90),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  buildNativeLocationRow(
                    label: "District",
                    value: district,
                    icon: Icons.location_city_rounded,
                  ),
                  const SizedBox(height: 10),
                  buildNativeLocationRow(
                    label: "Block",
                    value: block,
                    icon: Icons.account_tree_rounded,
                  ),
                  const SizedBox(height: 10),
                  buildNativeLocationRow(
                    label: "Village",
                    value: village,
                    icon: Icons.home_work_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildNativeLocationRow({
  required String label,
  required String value,
  required IconData icon,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.72),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFFE2E8F0),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF2563EB).withOpacity(0.08),
          ),
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "$label: ",
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF475569),
                    height: 1.3,
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

Widget _buildSoftGlow({
  required double size,
  required List<Color> colors,
}) {
  return ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    ),
  );
}

  Widget buildHofCard() {
    return buildSectionCard(
      title: "Head of Family",
      subtitle: "First entry will also be saved as member #1",
      icon: Icons.badge_rounded,
      child: Column(
        children: [
          TextField(
            controller: hofNameController,
            decoration: const InputDecoration(
              labelText: "HOF Name",
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: 16),
          buildSegmentedSelection(
            title: "HOF Type",
            options: const [
              ChoiceOption('father', 'Father'),
              ChoiceOption('mother', 'Mother'),
              ChoiceOption('guardian', 'Guardian'),
            ],
            selectedValue: hofType,
            onSelected: (value) {
              setState(() {
                hofType = value;
                if (value != 'guardian') {
                  hofGuardianSpecifyController.clear();
                }
              });
            },
          ),
          if (hofType == 'guardian') ...[
            const SizedBox(height: 16),
            TextField(
              controller: hofGuardianSpecifyController,
              decoration: const InputDecoration(
                labelText: "If guardian, specify",
                prefixIcon: Icon(Icons.badge_rounded),
              ),
            ),
          ],
          const SizedBox(height: 16),
          buildSegmentedSelection(
            title: "Gender",
            options: const [
              ChoiceOption('M', 'Male'),
              ChoiceOption('F', 'Female'),
            ],
            selectedValue: hofGender,
            onSelected: (value) {
              setState(() {
                hofGender = value;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: hofAgeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Age",
              prefixIcon: Icon(Icons.cake_rounded),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: hofMaritalStatus,
            decoration: const InputDecoration(
              labelText: "Marital Status",
              prefixIcon: Icon(Icons.favorite_outline_rounded),
            ),
            items: maritalOptions
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                hofMaritalStatus = value;
              });
            },
          ),
          const SizedBox(height: 16),
          buildYesNoField(
            title: "Part of SHG",
            value: hofIsShgMember,
            onChanged: (value) {
              setState(() {
                hofIsShgMember = value;
                if (!value) {
                  hofShgController.clear();
                }
              });
            },
          ),
          if (hofIsShgMember) ...[
            const SizedBox(height: 16),
            TextField(
              controller: hofShgController,
              decoration: const InputDecoration(
                labelText: "SHG Name / Code",
                prefixIcon: Icon(Icons.groups_rounded),
              ),
            ),
          ],
          const SizedBox(height: 16),
          buildYesNoField(
            title: "Is part of a special group",
            value: hofIsSpecialGroup,
            onChanged: (value) {
              setState(() {
                hofIsSpecialGroup = value;
                if (!value) {
                  hofSpecialGroup = null;
                }
              });
            },
          ),
          if (hofIsSpecialGroup) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: hofSpecialGroup,
              decoration: const InputDecoration(
                labelText: "Special Group Type",
                prefixIcon: Icon(Icons.workspace_premium_rounded),
              ),
              items: specialGroupOptions
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e,
                      child: Text(e),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  hofSpecialGroup = value;
                });
              },
            ),
          ],
          const SizedBox(height: 16),
          buildYesNoField(
            title: "Job Card Holder",
            value: hofIsJobCardHolder,
            onChanged: (value) {
              setState(() {
                hofIsJobCardHolder = value;
              });
            },
          ),
          const SizedBox(height: 16),
          buildYesNoField(
            title: "Has Aadhaar",
            value: hofHasAadhaar,
            onChanged: (value) {
              setState(() {
                hofHasAadhaar = value;
                if (!value) {
                  hofAadhaarController.clear();
                }
              });
            },
          ),
          if (hofHasAadhaar) ...[
            const SizedBox(height: 16),
            TextField(
              controller: hofAadhaarController,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: "Aadhaar Number",
                prefixIcon: Icon(Icons.credit_card_rounded),
                counterText: "",
              ),
            ),
          ],
          const SizedBox(height: 16),
          buildYesNoField(
            title: "Has EPIC",
            value: hofHasEpic,
            onChanged: (value) {
              setState(() {
                hofHasEpic = value;
                if (!value) {
                  hofEpicController.clear();
                }
              });
            },
          ),
          if (hofHasEpic) ...[
            const SizedBox(height: 16),
            TextField(
              controller: hofEpicController,
              decoration: const InputDecoration(
                labelText: "EPIC Number",
                prefixIcon: Icon(Icons.how_to_vote_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildMembersCard() {
    return buildSectionCard(
      title: "Other Members",
      subtitle: members.isEmpty
          ? "Add all household members other than the HOF"
          : "${members.length} member(s) added",
      icon: Icons.groups_rounded,
      child: Column(
        children: [
          if (members.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                "Add son, daughter, spouse, parent or any other member.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF475569),
                  height: 1.4,
                ),
              ),
            )
          else
            Column(
              children: List.generate(members.length, (index) {
                final member = members[index];

                return Container(
                  margin: EdgeInsets.only(
                    bottom: index == members.length - 1 ? 0 : 10,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFEAF2FF),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFF0F6FFF),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (member["member_name"] ?? "-").toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${formatRelationship(member["relationship_to_hof"]?.toString())} • ${member["gender"]} • ${member["age"]}",
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: "Edit",
                        onPressed: () => openMemberSheet(
                          existingMember: member,
                          index: index,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: "Delete",
                        onPressed: () {
                          setState(() {
                            members.removeAt(index);
                          });
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 220,
              child: OutlinedButton.icon(
                onPressed: openMemberSheet,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  members.isEmpty ? "Add Member" : "Add Another Member",
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String formatRelationship(String? value) {
    switch (value) {
      case 'spouse':
        return 'Spouse';
      case 'son':
        return 'Son';
      case 'daughter':
        return 'Daughter';
      case 'father':
        return 'Father';
      case 'mother':
        return 'Mother';
      case 'brother':
        return 'Brother';
      case 'sister':
        return 'Sister';
      case 'grandfather':
        return 'Grandfather';
      case 'grandmother':
        return 'Grandmother';
      case 'other':
        return 'Other';
      default:
        return 'Member';
    }
  }

  Widget buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEAF2FF),
                child: Icon(icon, color: const Color(0xFF0F6FFF), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget buildSegmentedSelection({
    required String title,
    required List<ChoiceOption> options,
    required String? selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = options.length >= 3 ? 3 : 2;
        final spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: spacing,
              runSpacing: 8,
              children: options.map((option) {
                final selected = selectedValue == option.value;

                return SizedBox(
                  width: itemWidth,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(option.value),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFDCEBFF)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF0F6FFF)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            option.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFF0F6FFF)
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget buildYesNoField({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildBooleanChip(
            label: 'YES',
            selected: value,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 8),
          _buildBooleanChip(
            label: 'NO',
            selected: !value,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _buildBooleanChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCEBFF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF0F6FFF) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF0F6FFF) : const Color(0xFF475569),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class ChoiceOption {
  final String value;
  final String label;

  const ChoiceOption(this.value, this.label);
}

class MemberFormSheet extends StatefulWidget {
  final Map<String, dynamic>? initialMember;

  const MemberFormSheet({
    super.key,
    this.initialMember,
  });

  @override
  State<MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<MemberFormSheet> {
  static const List<String> relationshipOptions = [
    'spouse',
    'son',
    'daughter',
    'father',
    'mother',
    'brother',
    'sister',
    'grandfather',
    'grandmother',
    'other',
  ];

  static const List<String> maritalOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Divorced',
  ];

  static const List<String> specialGroupOptions = [
    'Elderly',
    'PWD',
    'Adolescent Group',
  ];

  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController shgController = TextEditingController();
  final TextEditingController aadhaarController = TextEditingController();
  final TextEditingController epicController = TextEditingController();

  String? relationship;
  String? gender;
  String? maritalStatus;
  String? specialGroup;

  bool isShgMember = false;
  bool isJobCardHolder = false;
  bool isSpecialGroup = false;
  bool hasAadhaar = false;
  bool hasEpic = false;

  @override
  void initState() {
    super.initState();

    final m = widget.initialMember;
    if (m != null) {
      nameController.text = (m["member_name"] ?? "").toString();
      ageController.text = (m["age"] ?? "").toString();
      shgController.text = (m["shg_name_or_code"] ?? "").toString();
      aadhaarController.text = (m["aadhaar_no"] ?? "").toString();
      epicController.text = (m["epic_no"] ?? "").toString();

      relationship = m["relationship_to_hof"]?.toString();
      gender = m["gender"]?.toString();
      maritalStatus = m["marital_status"]?.toString();
      specialGroup = m["special_group"]?.toString();

      isShgMember = m["is_shg_member"] == true;
      isJobCardHolder = m["is_job_card_holder"] == true;
      isSpecialGroup = specialGroup != null && specialGroup!.isNotEmpty;
      hasAadhaar = m["has_aadhaar"] == true;
      hasEpic = m["has_epic"] == true;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    shgController.dispose();
    aadhaarController.dispose();
    epicController.dispose();
    super.dispose();
  }

  String? validateMember() {
    if (relationship == null) return 'Please select relationship';
    if (nameController.text.trim().isEmpty) return 'Please enter member name';
    if (gender == null) return 'Please select gender';

    final age = int.tryParse(ageController.text.trim());
    if (age == null || age < 0 || age > 130) {
      return 'Please enter valid age';
    }

    if (maritalStatus == null) return 'Please select marital status';

    if (isShgMember && shgController.text.trim().isEmpty) {
      return 'Please enter SHG name or code';
    }

    if (isSpecialGroup && specialGroup == null) {
      return 'Please select special group type';
    }

    if (hasAadhaar &&
        !RegExp(r'^\d{12}$').hasMatch(aadhaarController.text.trim())) {
      return 'Aadhaar must be 12 digits';
    }

    if (hasEpic && epicController.text.trim().isEmpty) {
      return 'Please enter EPIC number';
    }

    return null;
  }

  bool specialGroupIsPwd(String? value) {
    return value == 'PWD';
  }

  void submit() {
    final error = validateMember();

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          content: Text(error),
        ),
      );
      return;
    }

    Navigator.pop(context, {
      "device_member_ref": widget.initialMember?["device_member_ref"],
      "relationship_to_hof": relationship,
      "member_name": nameController.text.trim(),
      "gender": gender,
      "age": int.parse(ageController.text.trim()),
      "marital_status": maritalStatus,
      "is_shg_member": isShgMember,
      "shg_name_or_code": isShgMember ? shgController.text.trim() : null,
      "special_group": isSpecialGroup ? specialGroup : null,
      "is_job_card_holder": isJobCardHolder,
      "is_pwd": specialGroupIsPwd(specialGroup),
      "has_aadhaar": hasAadhaar,
      "aadhaar_no": hasAadhaar ? aadhaarController.text.trim() : null,
      "has_epic": hasEpic,
      "epic_no": hasEpic ? epicController.text.trim() : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialMember != null;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          10,
          18,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: 52,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.white.withOpacity(0.18),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEditing ? "Edit Member" : "Add Member",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: relationship,
                      decoration: const InputDecoration(
                        labelText: "Relationship to HOF",
                        prefixIcon: Icon(Icons.family_restroom_rounded),
                      ),
                      items: relationshipOptions
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(formatLabel(e)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          relationship = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Member Name",
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildSegmentedSelection(
                      title: "Gender",
                      options: const [
                        ChoiceOption('M', 'Male'),
                        ChoiceOption('F', 'Female'),
                      ],
                      selectedValue: gender,
                      onSelected: (value) {
                        setState(() {
                          gender = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Age",
                        prefixIcon: Icon(Icons.cake_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: maritalStatus,
                      decoration: const InputDecoration(
                        labelText: "Marital Status",
                        prefixIcon: Icon(Icons.favorite_outline_rounded),
                      ),
                      items: maritalOptions
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          maritalStatus = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    buildYesNoField(
                      title: "Part of SHG",
                      value: isShgMember,
                      onChanged: (value) {
                        setState(() {
                          isShgMember = value;
                          if (!value) {
                            shgController.clear();
                          }
                        });
                      },
                    ),
                    if (isShgMember) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: shgController,
                        decoration: const InputDecoration(
                          labelText: "SHG Name / Code",
                          prefixIcon: Icon(Icons.groups_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    buildYesNoField(
                      title: "Is part of a special group",
                      value: isSpecialGroup,
                      onChanged: (value) {
                        setState(() {
                          isSpecialGroup = value;
                          if (!value) {
                            specialGroup = null;
                          }
                        });
                      },
                    ),
                    if (isSpecialGroup) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: specialGroup,
                        decoration: const InputDecoration(
                          labelText: "Special Group Type",
                          prefixIcon: Icon(Icons.workspace_premium_rounded),
                        ),
                        items: specialGroupOptions
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e,
                                child: Text(e),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            specialGroup = value;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    buildYesNoField(
                      title: "Job Card Holder",
                      value: isJobCardHolder,
                      onChanged: (value) {
                        setState(() {
                          isJobCardHolder = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    buildYesNoField(
                      title: "Has Aadhaar",
                      value: hasAadhaar,
                      onChanged: (value) {
                        setState(() {
                          hasAadhaar = value;
                          if (!value) {
                            aadhaarController.clear();
                          }
                        });
                      },
                    ),
                    if (hasAadhaar) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: aadhaarController,
                        keyboardType: TextInputType.number,
                        maxLength: 12,
                        decoration: const InputDecoration(
                          labelText: "Aadhaar Number",
                          prefixIcon: Icon(Icons.credit_card_rounded),
                          counterText: "",
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    buildYesNoField(
                      title: "Has EPIC",
                      value: hasEpic,
                      onChanged: (value) {
                        setState(() {
                          hasEpic = value;
                          if (!value) {
                            epicController.clear();
                          }
                        });
                      },
                    ),
                    if (hasEpic) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: epicController,
                        decoration: const InputDecoration(
                          labelText: "EPIC Number",
                          prefixIcon: Icon(Icons.how_to_vote_rounded),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F6FFF), Color(0xFF38D39F)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: ElevatedButton(
                        onPressed: submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                        ),
                        child: Text(
                          isEditing ? "Update Member" : "Add Member",
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSegmentedSelection({
    required String title,
    required List<ChoiceOption> options,
    required String? selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = options.length >= 3 ? 3 : 2;
        final spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: spacing,
              runSpacing: 8,
              children: options.map((option) {
                final selected = selectedValue == option.value;

                return SizedBox(
                  width: itemWidth,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(option.value),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFDCEBFF)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF0F6FFF)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            option.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFF0F6FFF)
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget buildYesNoField({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildBooleanChip(
            label: 'YES',
            selected: value,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 8),
          _buildBooleanChip(
            label: 'NO',
            selected: !value,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _buildBooleanChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCEBFF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF0F6FFF) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF0F6FFF) : const Color(0xFF475569),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  String formatLabel(String value) {
    switch (value) {
      case 'spouse':
        return 'Spouse';
      case 'son':
        return 'Son';
      case 'daughter':
        return 'Daughter';
      case 'father':
        return 'Father';
      case 'mother':
        return 'Mother';
      case 'brother':
        return 'Brother';
      case 'sister':
        return 'Sister';
      case 'grandfather':
        return 'Grandfather';
      case 'grandmother':
        return 'Grandmother';
      case 'other':
        return 'Other';
      default:
        return value;
    }
  }
}