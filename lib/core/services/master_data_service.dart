// lib/core/services/master_data_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../features/survey/remote/master_service.dart';

class MasterDataService {
  final box = Hive.box('master_data_box');
  final MasterService api = MasterService();

  Future<void> syncMasterData() async {
    try {
      final districts = await api.fetchDistricts();
      final blocks = await api.fetchBlocks();
      final villages = await api.fetchVillages();

      await box.put("districts", districts);
      await box.put("blocks", blocks);
      await box.put("villages", villages);
      await box.put("master_synced_at", DateTime.now().toIso8601String());

      debugPrint("✅ Master data synced");
    } catch (e) {
      debugPrint("❌ Master sync error: $e");
      rethrow;
    }
  }

  List<Map<String, dynamic>> getDistricts() {
    final data = box.get("districts") ?? [];
    return List<Map<String, dynamic>>.from(data);
  }

  List<Map<String, dynamic>> getBlocks() {
    final data = box.get("blocks") ?? [];
    return List<Map<String, dynamic>>.from(data);
  }

  List<Map<String, dynamic>> getVillages() {
    final data = box.get("villages") ?? [];
    return List<Map<String, dynamic>>.from(data);
  }
}