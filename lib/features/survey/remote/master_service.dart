//lib\features\survey\remote\master_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/location_sorting.dart';

class MasterService {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchDistricts() async {
    final data = await supabase
        .from('districts')
        .select('id, name')
        .order('name');

    return LocationSorting.sortByName(List<Map<String, dynamic>>.from(data));
  }

  Future<List<Map<String, dynamic>>> fetchBlocks() async {
    final data = await supabase
        .from('blocks')
        .select('id, name, district_id')
        .order('name');

    return LocationSorting.sortByName(List<Map<String, dynamic>>.from(data));
  }

  Future<List<Map<String, dynamic>>> fetchVillages() async {
    List<Map<String, dynamic>> allData = [];

    int from = 0;
    const batchSize = 1000;

    while (true) {
      final data = await supabase
          .from('villages')
          .select('id, name, block_id, district_id, auth_code')
          .order('name')
          .range(from, from + batchSize - 1);

      if (data.isEmpty) break;

      allData.addAll(List<Map<String, dynamic>>.from(data));
      from += batchSize;
    }

    return LocationSorting.sortByName(allData);
  }
}