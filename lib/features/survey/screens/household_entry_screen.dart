import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/household_submission_service.dart';
import '../../../core/services/offline_survey_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/sync/survey_payload_builder.dart';
import '../household_entry/utils/household_entry_constants.dart';
import '../household_entry/utils/household_entry_validators.dart';
import '../household_entry/widgets/hof_section_card.dart';
import '../household_entry/widgets/location_header_card.dart';
import '../household_entry/widgets/member_form_sheet.dart';
import '../household_entry/widgets/members_section_card.dart';
import 'location_setup_screen.dart';

class HouseholdEntryScreen extends StatefulWidget {
  const HouseholdEntryScreen({super.key});

  @override
  State<HouseholdEntryScreen> createState() => _HouseholdEntryScreenState();
}

class _HouseholdEntryScreenState extends State<HouseholdEntryScreen>
    with WidgetsBindingObserver {
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
  final FocusNode hofNameFocusNode = FocusNode();
  final FocusNode membersSectionFocusNode = FocusNode(skipTraversal: true);
  final GlobalKey membersSectionKey = GlobalKey();

  String? hofType;
  String? hofGender;
  String? hofGenderErrorText;
  String? hofMaritalStatus;
  bool hofIsShgMember = false;
  bool hofIsJobCardHolder = false;
  bool hofIsPmayg = false;
  bool hofHasAadhaar = false;
  bool hofHasEpic = false;
  bool hofIsSpecialGroup = false;
  String? hofSpecialGroup;
  String? hofAadhaarErrorText;

  final List<Map<String, dynamic>> members = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rawSession = sessionBox.get('survey_session');
    if (rawSession is Map) {
      session = Map<String, dynamic>.from(rawSession);
    }
    hofNameController.addListener(_onHofCoreFieldChanged);
    hofAgeController.addListener(_onHofAgeChanged);
    hofAadhaarController.addListener(_onHofAadhaarChanged);
    _syncHofDependentState();
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
    hofNameFocusNode.dispose();
    membersSectionFocusNode.dispose();

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

    if (raw.contains('SocketException')) return 'No internet connection';
    if (raw.contains('TimeoutException')) return 'Connection timed out';
    if (raw.contains('PostgrestException')) {
      return raw.replaceAll('Exception: ', '');
    }

    return raw.replaceAll('Exception: ', '');
  }

  String? validateHof() {
    final aadhaarValidation = HouseholdEntryValidators.validateOptionalAadhaar(
      hofHasAadhaar ? hofAadhaarController.text : '',
    );
    if (aadhaarValidation != null) {
      return aadhaarValidation;
    }

    return HouseholdEntryValidators.validateHof(
      HofValidationInput(
        hofName: hofNameController.text,
        hofType: hofType,
        guardianSpecify: hofGuardianSpecifyController.text,
        hofGender: hofGender,
        age: hofAgeController.text,
        hofMaritalStatus: hofMaritalStatus,
        hofIsShgMember: hofIsShgMember,
        shgName: hofShgNameController.text,
        hofIsSpecialGroup: hofIsSpecialGroup,
        hofSpecialGroup: hofSpecialGroup,
      ),
    );
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
        relationshipOptions: _allowedMemberRelationshipOptions,
      ),
    );

    if (!mounted) return;

    if (result == null) {
      _focusMembersListSection();
      return;
    }

    final prepared = payloadBuilder.normalizeMember(Map<String, dynamic>.from(result));
    prepared['device_member_ref'] ??= offlineService.newDeviceRef('mem');

    setState(() {
      if (index != null) {
        members[index] = prepared;
      } else {
        members.add(prepared);
      }
    });

    _focusMembersListSection();
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

    final householdPayload = <String, dynamic>{
      'device_household_ref': offlineService.newDeviceRef('hh'),
      'district_id': session['district_id'],
      'block_id': session['block_id'],
      'village_id': session['village_id'],
      'hof_name': hofNameController.text.trim(),
      'hof_type': hofType,
      'guardian_specify':
          hofType == 'guardian' ? hofGuardianSpecifyController.text.trim() : null,
    };

    final allMembers = <Map<String, dynamic>>[
      {
        'device_member_ref': offlineService.newDeviceRef('mem'),
        'sort_order': 1,
        'relationship_to_hof': 'head_of_family',
        'member_name': hofNameController.text.trim(),
        'gender': hofGender,
        'age': HouseholdEntryValidators.parseAge(hofAgeController.text),
        'marital_status': hofMaritalStatus,
        'is_shg_member': hofIsShgMember,
        'shg_name': hofIsShgMember ? hofShgNameController.text.trim() : null,
        'shg_code': hofIsShgMember ? hofShgCodeController.text.trim() : null,
        'special_group': hofIsSpecialGroup ? hofSpecialGroup : null,
        'is_job_card_holder': hofIsJobCardHolder,
        'job_card_code':
            hofIsJobCardHolder ? hofJobCardCodeController.text.trim() : null,
        'is_pmayg': hofIsPmayg,
        'pmayg_code': hofIsPmayg ? hofPmaygCodeController.text.trim() : null,
        'has_aadhaar': hofHasAadhaar,
        'aadhaar_no': hofHasAadhaar ? hofAadhaarController.text.trim() : null,
        'has_epic': hofHasEpic,
        'epic_no': hofHasEpic ? hofEpicController.text.trim() : null,
      },
      ...members.asMap().entries.map((entry) {
        final i = entry.key;
        final member = Map<String, dynamic>.from(entry.value);

        member['device_member_ref'] ??= offlineService.newDeviceRef('mem');

        return {
          ...member,
          'sort_order': i + 2,
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

      if (!mounted || silent) return;

      final uploaded = result['uploaded'] ?? 0;
      final failed = result['failed'] ?? 0;
      final total = result['total'] ?? 0;
      final errors = (result['errors'] as List?)?.map((e) => '$e').toList() ??
          <String>[];

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
    } catch (e) {
      if (!mounted || silent) return;
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

  void clearForm({bool focusHofNameAfterClear = false}) {
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
      hofGenderErrorText = null;
      hofMaritalStatus = null;
      hofIsShgMember = false;
      hofIsJobCardHolder = false;
      hofIsPmayg = false;
      hofHasAadhaar = false;
      hofHasEpic = false;
      hofIsSpecialGroup = false;
      hofSpecialGroup = null;
      hofAadhaarErrorText = null;

      members.clear();
    });

    if (focusHofNameAfterClear) {
      _requestHofNameFocus();
    }
  }

  Future<void> onPullToRefresh() async {
    clearForm(focusHofNameAfterClear: false);
    await Future.wait([
      refreshPendingCount(),
      refreshConnectionState(showSnack: false),
    ]);
    if (!mounted) return;
    _requestHofNameFocus();
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

  void handleHofTypeChanged(String value) {
    setState(() {
      hofType = value;
      if (value != 'guardian') {
        hofGuardianSpecifyController.clear();
      }
      _syncHofDependentState();
    });
  }

  void handleShgChanged(bool value) {
    setState(() {
      hofIsShgMember = value;
      if (!value) {
        hofShgNameController.clear();
        hofShgCodeController.clear();
      }
    });
  }

  void handlePmaygChanged(bool value) {
    setState(() {
      hofIsPmayg = value;
      if (!value) {
        hofPmaygCodeController.clear();
      }
    });
  }

  void handleSpecialGroupChanged(bool value) {
    setState(() {
      hofIsSpecialGroup = value;
      if (!value) {
        hofSpecialGroup = null;
      }
      _syncHofDependentState();
    });
  }

  void handleJobCardChanged(bool value) {
    setState(() {
      hofIsJobCardHolder = value;
      if (!value) {
        hofJobCardCodeController.clear();
      }
    });
  }

  void handleAadhaarChanged(bool value) {
    setState(() {
      hofHasAadhaar = value;
      hofAadhaarErrorText = value
          ? HouseholdEntryValidators.validateOptionalAadhaar(
              hofAadhaarController.text,
            )
          : null;
      if (!value) {
        hofAadhaarController.clear();
      }
    });
  }

  void handleEpicChanged(bool value) {
    setState(() {
      hofHasEpic = value;
      if (!value) {
        hofEpicController.clear();
      }
    });
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

  int? get _hofAge => HouseholdEntryValidators.parseAge(hofAgeController.text);

  List<String> get _availableHofSpecialGroups =>
      HouseholdEntryValidators.allowedSpecialGroupsForAge(_hofAge);

  bool get _showHofShgField {
    if (hofType != 'father') return true;
    return hofIsSpecialGroup;
  }

  bool get _canAddMember =>
      HouseholdEntryValidators.isHeadOfFamilyReadyToAddMember(
        hofName: hofNameController.text,
        hofType: hofType,
        age: hofAgeController.text,
        hofGender: hofGender,
      );

  void _onHofCoreFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onHofAgeChanged() {
    if (!mounted) return;
    setState(() {
      _syncHofDependentState();
    });
  }

  void _onHofAadhaarChanged() {
    if (!mounted || !hofHasAadhaar) return;
    setState(() {
      hofAadhaarErrorText = HouseholdEntryValidators.validateOptionalAadhaar(
        hofAadhaarController.text,
      );
    });
  }

  void _syncHofDependentState() {
    hofGenderErrorText = HouseholdEntryValidators.validateHofGenderForType(
      hofType: hofType,
      hofGender: hofGender,
    );

    final allowedGroups = _availableHofSpecialGroups;
    if (hofSpecialGroup != null && !allowedGroups.contains(hofSpecialGroup)) {
      hofSpecialGroup = null;
    }

    if (hofType == 'father' && !_showHofShgField) {
      hofIsShgMember = false;
      hofShgNameController.clear();
      hofShgCodeController.clear();
    }
  }

  List<String> get _allowedMemberRelationshipOptions {
    final isSingle = (hofMaritalStatus ?? '').trim().toLowerCase() == 'single';
    if (!isSingle) return relationshipOptions;

    const blockedForSingle = {'spouse', 'son', 'daughter'};
    return relationshipOptions
        .where((option) => !blockedForSingle.contains(option.toLowerCase()))
        .toList();
  }

  void _requestHofNameFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(hofNameFocusNode);
    });
  }

  void _focusMembersListSection() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (membersSectionKey.currentContext != null) {
        Scrollable.ensureVisible(
          membersSectionKey.currentContext!,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
      FocusScope.of(context).requestFocus(membersSectionFocusNode);
    });
  }

  @override
  Widget build(BuildContext context) {
    final district = (session['district_name'] ?? '-').toString();
    final block = (session['block_name'] ?? '-').toString();
    final village = (session['village_name'] ?? '-').toString();

    return Scaffold(
      key: scaffoldKey,
      drawer: buildAppDrawer(),
      appBar: AppBar(
        title: const Text('MSRLS Survey'),
        actions: [
          IconButton(
            tooltip: 'Clear All',
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          children: [
            if (pendingCount > 0) buildPendingBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: onPullToRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
                  children: [
                    LocationHeaderCard(
                      district: district,
                      block: block,
                      village: village,
                    ),
                    const SizedBox(height: 18),
                    HofSectionCard(
                      data: HofSectionData(
                        hofNameController: hofNameController,
                        hofGuardianSpecifyController: hofGuardianSpecifyController,
                        hofAgeController: hofAgeController,
                        hofShgNameController: hofShgNameController,
                        hofShgCodeController: hofShgCodeController,
                        hofAadhaarController: hofAadhaarController,
                        hofEpicController: hofEpicController,
                        hofPmaygCodeController: hofPmaygCodeController,
                        hofJobCardCodeController: hofJobCardCodeController,
                        hofNameFocusNode: hofNameFocusNode,
                        hofType: hofType,
                        hofGender: hofGender,
                        hofGenderErrorText: hofGenderErrorText,
                        hofMaritalStatus: hofMaritalStatus,
                        hofIsShgMember: hofIsShgMember,
                        hofIsJobCardHolder: hofIsJobCardHolder,
                        hofIsPmayg: hofIsPmayg,
                        hofHasAadhaar: hofHasAadhaar,
                        hofHasEpic: hofHasEpic,
                        hofIsSpecialGroup: hofIsSpecialGroup,
                        hofSpecialGroup: hofSpecialGroup,
                        showShgField: _showHofShgField,
                        availableSpecialGroups: _availableHofSpecialGroups,
                        hofAadhaarErrorText: hofAadhaarErrorText,
                      ),
                      onHofTypeChanged: handleHofTypeChanged,
                      onHofGenderChanged: (value) => setState(() {
                        hofGender = value;
                        _syncHofDependentState();
                      }),
                      onMaritalStatusChanged: (value) => setState(() {
                        hofMaritalStatus = value;
                        _syncHofDependentState();
                      }),
                      onShgChanged: handleShgChanged,
                      onPmaygChanged: handlePmaygChanged,
                      onSpecialGroupChanged: handleSpecialGroupChanged,
                      onSpecialGroupTypeChanged: (value) => setState(() {
                        hofSpecialGroup = value;
                        _syncHofDependentState();
                      }),
                      onJobCardChanged: handleJobCardChanged,
                      onAadhaarChanged: handleAadhaarChanged,
                      onEpicChanged: handleEpicChanged,
                    ),
                    const SizedBox(height: 18),
                    Focus(
                      focusNode: membersSectionFocusNode,
                      child: KeyedSubtree(
                        key: membersSectionKey,
                        child: MembersSectionCard(
                          members: members,
                          onAdd: _canAddMember ? () => openMemberSheet() : null,
                          onSectionTap: _focusMembersListSection,
                          onEdit: (index) => openMemberSheet(
                            existingMember: members[index],
                            index: index,
                          ),
                          onDelete: (index) =>
                              setState(() => members.removeAt(index)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                    child: Icon(Icons.menu_rounded, color: Colors.white),
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
                    'Sync',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}
