// lib/features/survey/controller/location_controller.dart
import '../../../core/services/master_data_service.dart';
import '../utils/location_sorting.dart';


class LocationController {
  final MasterDataService cache = MasterDataService();

  List<Map<String, dynamic>> districts = [];
  List<Map<String, dynamic>> blocks = [];
  List<Map<String, dynamic>> villages = [];

  Future<void> load() async {
    districts = LocationSorting.sortByName(cache.getDistricts());
    blocks = LocationSorting.sortByName(cache.getBlocks());
    villages = LocationSorting.sortByName(cache.getVillages());

    final needsSync = districts.isEmpty ||
        blocks.isEmpty ||
        villages.isEmpty ||
        villages.any((v) => !v.containsKey('auth_code'));

    if (needsSync) {
      await cache.syncMasterData();

      districts = LocationSorting.sortByName(cache.getDistricts());
      blocks = LocationSorting.sortByName(cache.getBlocks());
      villages = LocationSorting.sortByName(cache.getVillages());
    }
  }

  List<Map<String, dynamic>> getBlocksByDistrict(String districtId) {
    return LocationSorting.sortByName(
      blocks.where((b) => b['district_id'] == districtId).toList(),
    );
  }

  List<Map<String, dynamic>> getVillages(String districtId, String blockId) {
    return LocationSorting.sortByName(
      villages
          .where(
            (v) =>
                v['district_id'] == districtId && v['block_id'] == blockId,
          )
          .toList(),
    );
  }
}