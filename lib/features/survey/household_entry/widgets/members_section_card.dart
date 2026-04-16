import 'package:flutter/material.dart';

import '../utils/household_entry_formatters.dart';
import 'survey_section_card.dart';

class MembersSectionCard extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final VoidCallback? onAdd;
  final void Function(int index) onEdit;
  final void Function(int index) onDelete;

  const MembersSectionCard({
    super.key,
    required this.members,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SurveySectionCard(
      title: 'Other Members',
      subtitle: members.isEmpty
          ? 'Add all household members other than the HOF'
          : '${members.length} member(s) added',
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
                'Add son, daughter, spouse, parent or any other member.',
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
                final meta = HouseholdEntryFormatters.buildMemberMeta(member);

                return Container(
                  margin: EdgeInsets.only(
                    bottom: index == members.length - 1 ? 0 : 10,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFEAF2FF),
                        child: Icon(
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
                              (member['member_name'] ?? '-').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${HouseholdEntryFormatters.formatRelationship(member['relationship_to_hof']?.toString())} • ${HouseholdEntryFormatters.formatGender(member['gender']?.toString())} • ${member['age']}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12.5,
                              ),
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                meta,
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
                        tooltip: 'Edit',
                        onPressed: () => onEdit(index),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete',
                        onPressed: () => onDelete(index),
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
                onPressed: onAdd,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  members.isEmpty ? 'Add Member' : 'Add Another Member',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
