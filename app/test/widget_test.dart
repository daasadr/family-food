import 'package:family_food/src/core/date_utils.dart';
import 'package:family_food/src/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('práce s daty', () {
    test('startOfWeek vrací pondělí', () {
      // 2026-08-05 je středa.
      final wednesday = DateTime(2026, 8, 5);
      expect(startOfWeek(wednesday), DateTime(2026, 8, 3));

      // Neděle patří do týdne, který začal předchozí pondělí.
      final sunday = DateTime(2026, 8, 9);
      expect(startOfWeek(sunday), DateTime(2026, 8, 3));

      // Pondělí je samo sobě začátkem.
      final monday = DateTime(2026, 8, 3);
      expect(startOfWeek(monday), monday);
    });

    test('apiDate formátuje na YYYY-MM-DD', () {
      expect(apiDate(DateTime(2026, 8, 5)), '2026-08-05');
      expect(apiDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('parseApiDate je opakem apiDate', () {
      final date = DateTime(2026, 8, 5);
      expect(parseApiDate(apiDate(date)), date);
    });

    test('weekRangeLabel zvládne přelom měsíce', () {
      expect(weekRangeLabel(DateTime(2026, 8, 3)), '3.–9. srpna');
      expect(weekRangeLabel(DateTime(2026, 8, 31)), '31. srpna – 6. září');
    });
  });

  group('modely', () {
    test('DaySummary počítá prázdné sloty', () {
      const summary = DaySummary(
        date: '2026-08-05',
        slotCount: 5,
        proposedCount: 1,
        confirmedCount: 2,
      );
      expect(summary.emptyCount, 2);
      expect(summary.isFullyPlanned, false);
    });

    test('DaySummary pozná plně naplánovaný den', () {
      const summary = DaySummary(
        date: '2026-08-05',
        slotCount: 3,
        proposedCount: 0,
        confirmedCount: 3,
      );
      expect(summary.isFullyPlanned, true);
      expect(summary.emptyCount, 0);
    });

    test('MealSlot najde potvrzený návrh', () {
      final slot = MealSlot.fromJson({
        'id': 'slot-1',
        'slotType': 'lunch',
        'isCustomSlot': false,
        'sortOrder': 2,
        'customLabel': null,
        'proposals': [
          _proposalJson(id: 'a', status: 'proposed'),
          _proposalJson(id: 'b', status: 'confirmed'),
        ],
      });

      expect(slot.confirmedProposal?.id, 'b');
      expect(slot.isEmpty, false);
      expect(slot.label, 'Oběd');
    });

    test('vlastní název slotu má přednost před typem', () {
      expect(
        slotTypeLabel(SlotType.custom, customLabel: 'Narozeninový dort'),
        'Narozeninový dort',
      );
      expect(slotTypeLabel(SlotType.breakfast), 'Snídaně');
    });
  });
}

Map<String, dynamic> _proposalJson({
  required String id,
  required String status,
}) =>
    {
      'id': id,
      'mealSlotId': 'slot-1',
      'title': 'Jídlo $id',
      'description': null,
      'photoUrl': null,
      'status': status,
      'createdAt': '2026-08-01T10:00:00.000Z',
      'proposedBy': {'id': 'u1', 'name': 'Tester', 'avatarUrl': null},
      'voteCount': 0,
      'votedByMe': false,
      'commentCount': 0,
    };
