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

  group('náhled smazání účtu', () {
    DeletionPreview preview(Map<String, dynamic> json) =>
        DeletionPreview.fromJson({
          'willDeleteFamily': false,
          'familyName': 'Novákovi',
          'memberCount': 2,
          'newOwnerName': null,
          'familyData': null,
          ...json,
        });

    test('poslednímu členovi hlásí smazání rodiny i s výčtem dat', () {
      final p = preview({
        'willDeleteFamily': true,
        'memberCount': 1,
        'familyData': {
          'proposals': 12,
          'comments': 3,
          'shoppingLists': 2,
          'galleryItems': 0,
          'plannedDays': 21,
        },
      });

      expect(p.willDeleteFamily, true);
      expect(p.familyData!.lines, [
        '21 dní naplánovaného jídelníčku',
        '12 návrhů jídel',
        '3 komentáře',
        '2 nákupní seznamy',
      ]);
    });

    test('prázdné položky se do výčtu nedostanou', () {
      final p = preview({
        'willDeleteFamily': true,
        'memberCount': 1,
        'familyData': {
          'proposals': 0,
          'comments': 0,
          'shoppingLists': 0,
          'galleryItems': 0,
          'plannedDays': 0,
        },
      });

      expect(p.familyData!.lines, isEmpty);
      expect(p.familyData!.isEmpty, true);
    });

    test('skloňuje podle počtu', () {
      FamilyDataSummary withProposals(int n) => FamilyDataSummary.fromJson({
            'proposals': n,
            'comments': 0,
            'shoppingLists': 0,
            'galleryItems': 0,
            'plannedDays': 0,
          });

      expect(withProposals(1).lines.single, '1 návrh jídel');
      expect(withProposals(3).lines.single, '3 návrhy jídel');
      expect(withProposals(9).lines.single, '9 návrhů jídel');
    });

    test('členovi v rodině s ostatními rodina nemizí', () {
      final p = preview({'memberCount': 3});

      expect(p.willDeleteFamily, false);
      expect(p.familyData, isNull);
    });

    test('odchod posledního vlastníka hlásí nástupce', () {
      final p = preview({'newOwnerName': 'Petra'});

      expect(p.willDeleteFamily, false);
      expect(p.newOwnerName, 'Petra');
    });
  });

  group('nákupní seznam', () {
    ShoppingList listWith(List<Map<String, dynamic>> items) =>
        ShoppingList.fromJson({
          'id': 'list-1',
          'rangeStart': '2026-08-03',
          'rangeEnd': '2026-08-09',
          'generatedAt': '2026-08-01T10:00:00.000Z',
          'generatedByAI': true,
          'items': items,
        });

    Map<String, dynamic> item({
      required String id,
      required String name,
      String? buyByDate,
      bool isChecked = false,
    }) =>
        {
          'id': id,
          'name': name,
          'isChecked': isChecked,
          'category': 'zelenina',
          'quantity': '1 kg',
          'buyByDate': buyByDate,
          'note': null,
        };

    test('seskupí položky podle dne nákupu', () {
      final list = listWith([
        item(id: 'a', name: 'treska', buyByDate: '2026-08-06'),
        item(id: 'b', name: 'brambory', buyByDate: '2026-08-03'),
        item(id: 'c', name: 'citron', buyByDate: '2026-08-06'),
      ]);

      final grouped = list.byBuyDate;
      expect(grouped.keys.toSet(), {'2026-08-06', '2026-08-03'});
      expect(grouped['2026-08-06'], hasLength(2));
      expect(grouped['2026-08-03'], hasLength(1));
    });

    test('položky bez data skončí pod klíčem null', () {
      final list = listWith([
        item(id: 'a', name: 'mouka'),
        item(id: 'b', name: 'treska', buyByDate: '2026-08-06'),
      ]);

      expect(list.byBuyDate[null], hasLength(1));
      expect(list.byBuyDate[null]!.first.name, 'mouka');
    });

    test('počítá odškrtnuté a pozná dokončený seznam', () {
      final partial = listWith([
        item(id: 'a', name: 'treska', isChecked: true),
        item(id: 'b', name: 'brambory'),
      ]);
      expect(partial.checkedCount, 1);
      expect(partial.isComplete, false);

      final done = listWith([
        item(id: 'a', name: 'treska', isChecked: true),
        item(id: 'b', name: 'brambory', isChecked: true),
      ]);
      expect(done.isComplete, true);
    });

    test('prázdný seznam není dokončený', () {
      expect(listWith([]).isComplete, false);
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
