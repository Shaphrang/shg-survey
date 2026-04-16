import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/household_submission_service.dart';
import '../../../core/services/offline_survey_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/sync/survey_payload_builder.dart';
import 'location_setup_screen.dart';
import '../widgets/survey_yes_no_field.dart';

class HouseholdEntryScreen extends StatefulWidget {
  const HouseholdEntryScreen({super.key});

  @override
  State<HouseholdEntryScreen> createState() => _HouseholdEntryScreenState();
}

class _HouseholdEntryScreenState extends State<HouseholdEntryScreen> with WidgetsBindingObserver {
  final Box sessionBox = Hive.box('session_box');
  final OfflineSurveyService offlineService = OfflineSurveyService();
  final SyncService syncService = SyncService();
  final InternetConnection internetConnection = InternetConnection();
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  final HouseholdSubmissionService householdSubmissionService =
      HouseholdSubmissionService();
  final SurveyPayloadBuilder payloadBuilder = const SurveyPayloadBuilder();

  StreamSubscription<InternetStatus>? internetSubscription;

  Map<String, dynamic> session = {};

  bool isOnline = false;
  bool isCheckingStatus = true;
  bool isSaving = false;
  bool isSyncing = false;
  int pendingCount = 0;
  String? lastConnectionMessage;
  String? _lastSavedFingerprint;
  DateTime? _lastSavedAt;

  final TextEditingController hofNameController = TextEditingController();
  final TextEditingController hofGuardianSpecifyController =
      TextEditingController();
  final TextEditingController hofAgeController = TextEditingController();
  final TextEditingController hofShgNameController = TextEditingController();
  final TextEditingController hofShgCodeController = TextEditingController();
  final TextEditingController hofAadhaarController = TextEditingController();
  final TextEditingController hofEpicController = TextEditingController();
  final TextEditingController hofPmaygCodeController = TextEditingController();
  final TextEditingController hofJobCardCodeController = TextEditingController();

  String? hofType;
  String? hofGender;
  String? hofMaritalStatus;
  bool hofIsShgMember = false;
  bool hofIsJobCardHolder = false;
  bool hofIsPmayg = false;
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
    WidgetsBinding.instance.addObserver(this);
    final rawSession = sessionBox.get('survey_session');
    if (rawSession is Map) {
      session = Map<String, dynamic>.from(rawSession);
    }
    bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    internetSubscription?.cancel();

    hofNameController.dispose();
    hofGuardianSpecifyController.dispose();
    hofAgeController.dispose();
    hofShgNameController.dispose();
    hofShgCodeController.dispose();
    hofAadhaarController.dispose();
    hofEpicController.dispose();
    hofPmaygCodeController.dispose();
    hofJobCardCodeController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncPending(silent: true));
    }
  }

  Future<void> bootstrap() async {
    await refreshPendingCount();
    final reachable = await refreshConnectionState(showSnack: false);
    if (reachable) {
      await syncPending(silent: true);
    }

    internetSubscription =
        internetConnection.onStatusChange.listen((InternetStatus _) async {
      final reachable = await refreshConnectionState(showSnack: false);
      if (reachable) {
        await syncPending(silent: true);
      }
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

  int? parseAge(String text) {
    return int.tryParse(text.trim());
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

    if (hofIsShgMember && hofShgNameController.text.trim().isEmpty) {
      return 'Please enter SHG name';
    }

    if (hofIsSpecialGroup && hofSpecialGroup == null) {
      return 'Please select the special group type';
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

    final prepared = payloadBuilder.normalizeMember(Map<String, dynamic>.from(result));
    prepared['device_member_ref'] ??= offlineService.newDeviceRef('mem');

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

    final submissionFingerprint = [
      session['district_id'],
      session['block_id'],
      session['village_id'],
      hofNameController.text.trim().toLowerCase(),
      hofType,
      hofGender,
      hofAgeController.text.trim(),
      members.length,
    ].join('|');

    final now = DateTime.now().toUtc();
    if (_lastSavedFingerprint == submissionFingerprint &&
        _lastSavedAt != null &&
        now.difference(_lastSavedAt!) <= const Duration(seconds: 10)) {
      showAppSnack(
        'This survey was just saved. Please avoid duplicate submissions.',
        isError: true,
      );
      return;
    }

    final deviceHouseholdRef = offlineService.newDeviceRef('hh');

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
        "device_member_ref": offlineService.newDeviceRef('mem'),
        "sort_order": 1,
        "relationship_to_hof": "head_of_family",
        "member_name": hofNameController.text.trim(),
        "gender": hofGender,
        "age": parseAge(hofAgeController.text),
        "marital_status": hofMaritalStatus,
        "is_shg_member": hofIsShgMember,
        "shg_name": hofIsShgMember ? hofShgNameController.text.trim() : null,
        "shg_code": hofIsShgMember ? hofShgCodeController.text.trim() : null,
        "special_group": hofIsSpecialGroup ? hofSpecialGroup : null,
        "is_job_card_holder": hofIsJobCardHolder,
        "job_card_code":
            hofIsJobCardHolder ? hofJobCardCodeController.text.trim() : null,
        "is_pmayg": hofIsPmayg,
        "pmayg_code": hofIsPmayg ? hofPmaygCodeController.text.trim() : null,
        "has_aadhaar": hofHasAadhaar,
        "aadhaar_no": hofHasAadhaar ? hofAadhaarController.text.trim() : null,
        "has_epic": hofHasEpic,
        "epic_no": hofHasEpic ? hofEpicController.text.trim() : null,
      },
      ...members.asMap().entries.map((entry) {
        final i = entry.key;
        final member = Map<String, dynamic>.from(entry.value);

        member["device_member_ref"] ??= offlineService.newDeviceRef('mem');

        return {
          ...member,
          "sort_order": i + 2,
        };
      }),
    ];

    setState(() {
      isSaving = true;
    });

    try {
      final result = await householdSubmissionService.saveWithOnlineFirstFallback(
        household: householdPayload,
        members: allMembers,
      );
      await refreshPendingCount();
      await refreshConnectionState(showSnack: false);
      _lastSavedFingerprint = submissionFingerprint;
      _lastSavedAt = now;
      clearForm();

      if (!mounted) return;
      final isOffline = result.status == HouseholdSaveStatus.savedOfflinePending;
      showAppSnack(result.message, isError: false);

      if (isOnline) {
        unawaited(syncPending(silent: true));
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnack('Failed to save locally: ${readableError(e)}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> syncPending({bool silent = false}) async {
    if (isSyncing || pendingCount == 0) return;

    final canReachServer = await refreshConnectionState(showSnack: false);
    if (!canReachServer) {
      if (!silent) {
        showAppSnack(
          'Server not reachable. Pending households remain offline.',
          isError: true,
        );
      }
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
      final total = result["total"] ?? 0;
      final errors = (result["errors"] as List?)?.map((e) => '$e').toList() ?? <String>[];

      if (!silent) {
        if (total == 0 && errors.isNotEmpty) {
          showAppSnack(
            'Nothing synced: ${errors.first}',
            isError: true,
          );
        } else if (failed == 0) {
          showAppSnack('$uploaded household(s) synced successfully');
        } else {
          showAppSnack(
            '$uploaded synced, $failed failed. ${errors.isNotEmpty ? 'Reason: ${errors.first}' : ''}',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      if (!silent) {
        showAppSnack(
          'Sync failed: ${readableError(e)}',
          isError: true,
        );
      }
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
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      hofNameController.clear();
      hofGuardianSpecifyController.clear();
      hofAgeController.clear();
      hofShgNameController.clear();
      hofShgCodeController.clear();
      hofAadhaarController.clear();
      hofEpicController.clear();
      hofPmaygCodeController.clear();
      hofJobCardCodeController.clear();

      hofType = null;
      hofGender = null;
      hofMaritalStatus = null;
      hofIsShgMember = false;
      hofIsJobCardHolder = false;
      hofIsPmayg = false;
      hofHasAadhaar = false;
      hofHasEpic = false;
      hofIsSpecialGroup = false;
      hofSpecialGroup = null;

      members.clear();
    });
  }

  Future<void> onPullToRefresh() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.wait([
      refreshPendingCount(),
      refreshConnectionState(showSnack: false),
    ]);

    if (mounted) {
      setState(() {});
    }
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
        ? 'Saved locally first, then synced automatically'
        : 'Stored locally and queued for sync';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      drawer: buildAppDrawer(),
      appBar: AppBar(
        title: const Text("MSRLS Survey"),
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
            child: RefreshIndicator(
              onRefresh: onPullToRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
          ),
        ],
      ),
    );
  }

  Widget buildAppDrawer() {
    final pendingText = pendingCount == 1
        ? '1 household pending'
        : '$pendingCount households pending';
    final failedCount = offlineService.getFailedCount();

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
              subtitle: Text('$pendingText • $failedCount failed'),
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
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Retry failed submissions'),
              subtitle: const Text('Moves transient failures back to pending'),
              onTap: () async {
                Navigator.pop(context);
                await syncService.retryFailedNow();
                await refreshPendingCount();
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

  Widget buildLocationPill(IconData icon, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: const Color(0xFF0F6FFF).withOpacity(0.08),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: const Color(0xFF0F6FFF),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF334155),
          ),
        ),
      ],
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
          buildAnimatedConditional(
            show: hofType == 'guardian',
            child: TextField(
              controller: hofGuardianSpecifyController,
              decoration: const InputDecoration(
                labelText: "If guardian, specify",
                prefixIcon: Icon(Icons.badge_rounded),
              ),
            ),
          ),
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
          SurveyYesNoField(
            title: "Part of SHG",
            value: hofIsShgMember,
            onChanged: (value) {
              setState(() {
                hofIsShgMember = value;
                if (!value) {
                  hofShgNameController.clear();
                  hofShgCodeController.clear();
                }
              });
            },
          ),
          buildAnimatedConditional(
            show: hofIsShgMember,
            child: Column(
              children: [
                TextField(
                  controller: hofShgNameController,
                  decoration: const InputDecoration(
                    labelText: "SHG Name",
                    prefixIcon: Icon(Icons.groups_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hofShgCodeController,
                  decoration: const InputDecoration(
                    labelText: "SHG Code (Optional)",
                    prefixIcon: Icon(Icons.qr_code_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
            title: "PMAY-G Beneficiary",
            value: hofIsPmayg,
            onChanged: (value) {
              setState(() {
                hofIsPmayg = value;
                if (!value) {
                  hofPmaygCodeController.clear();
                }
              });
            },
          ),
          buildAnimatedConditional(
            show: hofIsPmayg,
            child: TextField(
              controller: hofPmaygCodeController,
              decoration: const InputDecoration(
                labelText: "PMAY-G Code (Optional)",
                prefixIcon: Icon(Icons.home_work_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
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
          buildAnimatedConditional(
            show: hofIsSpecialGroup,
            child: DropdownButtonFormField<String>(
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
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
            title: "Job Card Holder",
            value: hofIsJobCardHolder,
            onChanged: (value) {
              setState(() {
                hofIsJobCardHolder = value;
                if (!value) {
                  hofJobCardCodeController.clear();
                }
              });
            },
          ),
          buildAnimatedConditional(
            show: hofIsJobCardHolder,
            child: TextField(
              controller: hofJobCardCodeController,
              decoration: const InputDecoration(
                labelText: "Job Card Code (Optional)",
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
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
          buildAnimatedConditional(
            show: hofHasAadhaar,
            child: TextField(
              controller: hofAadhaarController,
              decoration: const InputDecoration(
                labelText: "Aadhaar Number (Optional)",
                prefixIcon: Icon(Icons.credit_card_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SurveyYesNoField(
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
          buildAnimatedConditional(
            show: hofHasEpic,
            child: TextField(
              controller: hofEpicController,
              decoration: const InputDecoration(
                labelText: "EPIC Number (Optional)",
                prefixIcon: Icon(Icons.how_to_vote_rounded),
              ),
            ),
          ),
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
                              "${formatRelationship(member["relationship_to_hof"]?.toString())} • ${formatGender(member["gender"]?.toString())} • ${member["age"]}",
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12.5,
                              ),
                            ),
                            if (buildMemberMeta(member).isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                buildMemberMeta(member),
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
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

  String formatGender(String? value) {
    switch (value) {
      case 'M':
        return 'Male';
      case 'F':
        return 'Female';
      default:
        return '-';
    }
  }

  String buildMemberMeta(Map<String, dynamic> member) {
    final parts = <String>[];
    final relationship = member['relationship_to_hof']?.toString();
    final relationshipOther = member['relationship_to_hof_other']?.toString();
    if (relationship == 'other' &&
        relationshipOther != null &&
        relationshipOther.trim().isNotEmpty) {
      parts.add('Other: ${relationshipOther.trim()}');
    }

    if (member['is_shg_member'] == true) {
      final shgName = member['shg_name']?.toString();
      final shgCode = member['shg_code']?.toString();
      if (shgName != null && shgName.trim().isNotEmpty) {
        parts.add('SHG: ${shgName.trim()}');
      }
      if (shgCode != null && shgCode.trim().isNotEmpty) {
        parts.add('SHG Code: ${shgCode.trim()}');
      }
    }

    if (member['has_aadhaar'] == true) {
      final aadhaar = member['aadhaar_no']?.toString();
      if (aadhaar != null && aadhaar.trim().isNotEmpty) {
        parts.add('Aadhaar: ${aadhaar.trim()}');
      }
    }
    if (member['has_epic'] == true) {
      final epic = member['epic_no']?.toString();
      if (epic != null && epic.trim().isNotEmpty) {
        parts.add('EPIC: ${epic.trim()}');
      }
    }
    if (member['is_pmayg'] == true) {
      final pmayg = member['pmayg_code']?.toString();
      if (pmayg != null && pmayg.trim().isNotEmpty) {
        parts.add('PMAY-G: ${pmayg.trim()}');
      }
    }
    if (member['is_job_card_holder'] == true) {
      final jobCard = member['job_card_code']?.toString();
      if (jobCard != null && jobCard.trim().isNotEmpty) {
        parts.add('Job Card: ${jobCard.trim()}');
      }
    }
    return parts.join(' • ');
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
    String? errorText,
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
                        if (errorText != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorText,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget buildAnimatedConditional({
    required bool show,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: show
          ? Padding(
              key: ValueKey<bool>(show),
              padding: const EdgeInsets.only(top: 16),
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey<bool>(false)),
    );
  }

}

class ChoiceOption {
  final String value;
  final String label;

  const ChoiceOption(this.value, this.label);
}

class _LocationChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _LocationChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
                    Icon(icon, size: 16, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
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
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final SurveyPayloadBuilder payloadBuilder = const SurveyPayloadBuilder();
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
  final TextEditingController relationshipOtherController =
      TextEditingController();
  final TextEditingController shgNameController = TextEditingController();
  final TextEditingController shgCodeController = TextEditingController();
  final TextEditingController aadhaarController = TextEditingController();
  final TextEditingController epicController = TextEditingController();
  final TextEditingController pmaygCodeController = TextEditingController();
  final TextEditingController jobCardCodeController = TextEditingController();

  String? relationship;
  String? gender;
  String? maritalStatus;
  String? specialGroup;

  bool isShgMember = false;
  bool isJobCardHolder = false;
  bool isPmayg = false;
  bool isSpecialGroup = false;
  bool hasAadhaar = false;
  bool hasEpic = false;
  bool hasSubmitted = false;

  String? relationshipError;
  String? genderError;
  String? maritalStatusError;

  @override
  void initState() {
    super.initState();

    final rawMember = widget.initialMember;
    final m = rawMember == null
        ? null
        : payloadBuilder.normalizeMember(Map<String, dynamic>.from(rawMember));
    if (m != null) {
      nameController.text = (m["member_name"] ?? "").toString();
      ageController.text = (m["age"] ?? "").toString();
      relationshipOtherController.text =
          (m["relationship_to_hof_other"] ?? "").toString();
      shgNameController.text = (m["shg_name"] ?? "").toString();
      shgCodeController.text = (m["shg_code"] ?? "").toString();
      aadhaarController.text = (m["aadhaar_no"] ?? "").toString();
      epicController.text = (m["epic_no"] ?? "").toString();
      pmaygCodeController.text = (m["pmayg_code"] ?? "").toString();
      jobCardCodeController.text = (m["job_card_code"] ?? "").toString();

      relationship = m["relationship_to_hof"]?.toString();
      gender = m["gender"]?.toString();
      maritalStatus = m["marital_status"]?.toString();
      specialGroup = m["special_group"]?.toString();

      isShgMember = m["is_shg_member"] == true;
      isJobCardHolder = m["is_job_card_holder"] == true;
      isPmayg = m["is_pmayg"] == true;
      isSpecialGroup = specialGroup != null && specialGroup!.isNotEmpty;
      hasAadhaar = m["has_aadhaar"] == true;
      hasEpic = m["has_epic"] == true;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    relationshipOtherController.dispose();
    shgNameController.dispose();
    shgCodeController.dispose();
    aadhaarController.dispose();
    epicController.dispose();
    pmaygCodeController.dispose();
    jobCardCodeController.dispose();
    super.dispose();
  }

  void submit() {
        final valid = formKey.currentState?.validate() ?? false;

    setState(() {
      hasSubmitted = true;
      relationshipError =
          relationship == null ? 'Please select relationship' : null;
      genderError = gender == null ? 'Please select gender' : null;
      maritalStatusError =
          maritalStatus == null ? 'Please select marital status' : null;
    });

    if (!valid ||
        relationshipError != null ||
        genderError != null ||
        maritalStatusError != null) {
      return;
    }

    Navigator.pop(context, {
      "device_member_ref": widget.initialMember?["device_member_ref"],
      "relationship_to_hof": relationship,
      "relationship_to_hof_other":
          relationship == 'other' ? relationshipOtherController.text.trim() : null,
      "member_name": nameController.text.trim(),
      "gender": gender,
      "age": int.parse(ageController.text.trim()),
      "marital_status": maritalStatus,
      "is_shg_member": isShgMember,
      "shg_name": isShgMember ? shgNameController.text.trim() : null,
      "shg_code": isShgMember ? shgCodeController.text.trim() : null,
      "special_group": isSpecialGroup ? specialGroup : null,
      "is_job_card_holder": isJobCardHolder,
      "job_card_code":
          isJobCardHolder ? jobCardCodeController.text.trim() : null,
      "is_pmayg": isPmayg,
      "pmayg_code": isPmayg ? pmaygCodeController.text.trim() : null,
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
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 52,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white.withOpacity(0.18),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEditing ? "Edit Member" : "Add Member",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
                            const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  child: Form(
                    key: formKey,
                    autovalidateMode: hasSubmitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: relationship,
                            decoration: InputDecoration(
                              labelText: "Relationship to HOF",
                              prefixIcon: const Icon(Icons.family_restroom_rounded),
                              errorText: relationshipError,
                            ),
                          
                            items: relationshipOptions
                                .map((e) => DropdownMenuItem<String>(
                                      value: e,
                                      child: Text(formatLabel(e)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                relationship = value;
                                relationshipError = null;
                                if (value != 'other') {
                                  relationshipOtherController.clear();
                                }
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: relationship == 'other',
                            child: TextFormField(
                              controller: relationshipOtherController,
                              decoration: const InputDecoration(
                                labelText: "Specify Relationship",
                                prefixIcon: Icon(Icons.edit_note_rounded),
                              ),
                              validator: (value) {
                                if (relationship == 'other' &&
                                    (value == null || value.trim().isEmpty)) {
                                  return 'Please specify relationship';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: "Member Name",
                              prefixIcon: Icon(Icons.person_rounded),

                            ),
                                                      validator: (value) => (value == null || value.trim().isEmpty)
                                ? 'Please enter member name'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          buildSegmentedSelection(
                            title: "Gender",
                            options: const [
                              ChoiceOption('M', 'Male'),
                              ChoiceOption('F', 'Female'),
                            ],
                            selectedValue: gender,
                            errorText: genderError,
                            onSelected: (value) {
                              setState(() {
                                gender = value;
                                genderError = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Age",
                              prefixIcon: Icon(Icons.cake_rounded),
                            ),
                            validator: (value) {
                              final age = int.tryParse((value ?? '').trim());
                              if (age == null || age < 0 || age > 130) {
                                return 'Please enter valid age';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: maritalStatus,
                            decoration: InputDecoration(
                              labelText: "Marital Status",
                              prefixIcon: const Icon(Icons.favorite_outline_rounded),
                              errorText: maritalStatusError,
                            ),
                            items: maritalOptions
                                .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                maritalStatus = value;
                                maritalStatusError = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: "Part of SHG",
                            value: isShgMember,
                            onChanged: (value) {
                              setState(() {
                                isShgMember = value;
                                if (!value) {
                                  shgNameController.clear();
                                  shgCodeController.clear();
                                }
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: isShgMember,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: shgNameController,
                                  decoration: const InputDecoration(
                                    labelText: "SHG Name",
                                    prefixIcon: Icon(Icons.groups_rounded),
                                  ),
                                  validator: (value) {
                                    if (isShgMember &&
                                        (value == null ||
                                            value.trim().isEmpty)) {
                                      return 'Please enter SHG name';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: shgCodeController,
                                  decoration: const InputDecoration(
                                    labelText: "SHG Code (Optional)",
                                    prefixIcon: Icon(Icons.qr_code_rounded),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: "Is part of a special group",
                            value: isSpecialGroup,
                            onChanged: (value) {
                              setState(() {
                                isSpecialGroup = value;
                                if (!value) specialGroup = null;
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: isSpecialGroup,
                            child: DropdownButtonFormField<String>(
                              initialValue: specialGroup,
                              decoration: const InputDecoration(
                                labelText: "Special Group Type",
                                prefixIcon: Icon(Icons.workspace_premium_rounded),
                              ),
                              items: specialGroupOptions
                                  .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  specialGroup = value;
                                });
                              },
                              validator: (value) {
                                if (isSpecialGroup && value == null) {
                                  return 'Please select special group type';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: "Job Card Holder",
                            value: isJobCardHolder,
                            onChanged: (value) {
                              setState(() {
                                isJobCardHolder = value;
                                if (!value) {
                                  jobCardCodeController.clear();
                                }
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: isJobCardHolder,
                            child: TextFormField(
                              controller: jobCardCodeController,
                              decoration: const InputDecoration(
                                labelText: "Job Card Code (Optional)",
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: "PMAY-G Beneficiary",
                            value: isPmayg,
                            onChanged: (value) {
                              setState(() {
                                isPmayg = value;
                                if (!value) {
                                  pmaygCodeController.clear();
                                }
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: isPmayg,
                            child: TextFormField(
                              controller: pmaygCodeController,
                              decoration: const InputDecoration(
                                labelText: "PMAY-G Code (Optional)",
                                prefixIcon: Icon(Icons.home_work_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: "Has Aadhaar",
                            value: hasAadhaar,
                            onChanged: (value) {
                              setState(() {
                                hasAadhaar = value;
                                if (!value) aadhaarController.clear();
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: hasAadhaar,
                            child: TextFormField(
                              controller: aadhaarController,
                              decoration: const InputDecoration(
                                labelText: "Aadhaar Number (Optional)",
                                prefixIcon: Icon(Icons.credit_card_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SurveyYesNoField(
                            title: "Has EPIC",
                            value: hasEpic,
                            onChanged: (value) {
                              setState(() {
                                hasEpic = value;
                                if (!value) epicController.clear();
                              });
                            },
                          ),
                          buildAnimatedConditional(
                            show: hasEpic,
                            child: TextFormField(
                              controller: epicController,
                              decoration: const InputDecoration(
                                labelText: "EPIC Number (Optional)",
                                prefixIcon: Icon(Icons.how_to_vote_rounded),
                              ),
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
                                    colors: [Color(0xFF0F766E), Color(0xFF10B981)],
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
                ),
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
    String? errorText,
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
                        if (errorText != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorText,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

    Widget buildAnimatedConditional({
    required bool show,
    required Widget child,
  }) {
        return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: show
          ? Padding(
              key: ValueKey<bool>(show),
              padding: const EdgeInsets.only(top: 16),
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey<bool>(false)),
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
