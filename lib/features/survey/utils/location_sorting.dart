class LocationSorting {
  const LocationSorting._();

  static List<Map<String, dynamic>> sortByName(
    List<Map<String, dynamic>> source,
  ) {
    final indexed = source.asMap().entries.toList();
    indexed.sort((a, b) {
      final aName = (a.value['name'] ?? '').toString().trim().toLowerCase();
      final bName = (b.value['name'] ?? '').toString().trim().toLowerCase();
      final byName = aName.compareTo(bName);
      if (byName != 0) return byName;
      return a.key.compareTo(b.key);
    });

    return indexed
        .map((entry) => Map<String, dynamic>.from(entry.value))
        .toList(growable: false);
  }
}