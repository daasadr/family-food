@Tags(['integration'])
library;

import 'package:family_food/src/core/api_client.dart';
import 'package:family_food/src/core/api_service.dart';
import 'package:family_food/src/core/date_utils.dart';
import 'package:family_food/src/core/token_storage.dart';
import 'package:family_food/src/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ověřuje, že aplikace rozumí tomu, co backend skutečně posílá — tedy že
/// modely a fromJson sedí na reálné odpovědi, ne jen na naše představy.
///
/// Vyžaduje běžící backend na localhost:3000. Spustí se jen na vyžádání:
///   flutter test --tags integration
void main() {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  late ApiService api;
  late InMemoryTokenStorage storage;

  String uniqueEmail() =>
      'app-test-${DateTime.now().microsecondsSinceEpoch}@test.local';

  /// Datum v budoucnu uvnitř povoleného tříměsíčního okna.
  String futureDate() => apiDate(today().add(const Duration(days: 7)));

  setUp(() {
    storage = InMemoryTokenStorage();
    api = ApiService(ApiClient(baseUrl: baseUrl, storage: storage));
  });

  Future<void> signUpWithFamily(String familyName) async {
    final registered = await api.register(
      email: uniqueEmail(),
      password: 'heslo12345',
      name: 'Testovací uživatel',
    );
    await storage.saveTokens(
      accessToken: registered.tokens.accessToken,
      refreshToken: registered.tokens.refreshToken,
    );

    final created = await api.createFamily(familyName);
    await storage.saveTokens(
      accessToken: created.tokens.accessToken,
      refreshToken: created.tokens.refreshToken,
    );
  }

  test('registrace a založení rodiny vrátí použitelné modely', () async {
    await signUpWithFamily('Testovací rodina');

    final family = await api.getFamily();
    expect(family.name, 'Testovací rodina');
    expect(family.members, hasLength(1));
    expect(family.members.first.isOwner, isTrue);

    final me = await api.me();
    expect(me.hasFamily, isTrue);
    expect(me.familyId, family.id);
  });

  test('den obsahuje sloty z výchozí šablony', () async {
    await signUpWithFamily('Rodina se šablonou');

    final day = await api.getDay(futureDate());
    expect(day.slots, hasLength(5));
    expect(
      day.slots.map((s) => s.slotType),
      [
        SlotType.breakfast,
        SlotType.snack1,
        SlotType.lunch,
        SlotType.snack2,
        SlotType.dinner,
      ],
    );
    expect(day.slots.first.label, 'Snídaně');
    expect(day.slots.every((s) => s.isEmpty), isTrue);
  });

  test('celý tok návrhu jídla projde přes modely aplikace', () async {
    await signUpWithFamily('Rodina s návrhem');
    final date = futureDate();

    final day = await api.getDay(date);
    final lunch = day.slots.firstWhere((s) => s.slotType == SlotType.lunch);

    final proposal = await api.createProposal(
      slotId: lunch.id,
      title: 'Svíčková',
      description: 'S houskovým knedlíkem',
    );
    expect(proposal.title, 'Svíčková');
    expect(proposal.status, ProposalStatus.proposed);
    expect(proposal.voteCount, 0);

    final voted = await api.vote(proposal.id);
    expect(voted.voteCount, 1);
    expect(voted.votedByMe, isTrue);

    await api.addComment(proposalId: proposal.id, text: 'Těším se!');
    final comments = await api.listComments(proposal.id);
    expect(comments, hasLength(1));
    expect(comments.first.text, 'Těším se!');

    final confirmed = await api.confirmProposal(proposal.id);
    expect(confirmed.isConfirmed, isTrue);

    final afterConfirm = await api.getDay(date);
    final lunchAfter =
        afterConfirm.slots.firstWhere((s) => s.slotType == SlotType.lunch);
    expect(lunchAfter.confirmedProposal?.id, proposal.id);

    final unlocked = await api.unlockProposal(proposal.id);
    expect(unlocked.status, ProposalStatus.proposed);
  });

  test('týdenní přehled má 7 dní s počty pro indikátory', () async {
    await signUpWithFamily('Rodina s týdnem');

    final week = await api.getWeek(apiDate(startOfWeek(today())));
    expect(week.days, hasLength(7));
    expect(week.days.first.slotCount, 5);
    expect(week.days.first.emptyCount, 5);
  });

  test('chyba z API dorazí jako ApiException se stabilním kódem', () async {
    await signUpWithFamily('Rodina s chybou');

    // Za hranicí tříměsíčního okna plánování.
    final tooFar = apiDate(today().add(const Duration(days: 200)));
    await expectLater(
      api.getDay(tooFar),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'BEYOND_PLANNING_WINDOW'),
      ),
    );
  });

  test('globální galerie je naplněná a dá se prohledávat', () async {
    await signUpWithFamily('Rodina s galerií');

    final all = await api.gallery();
    expect(all, isNotEmpty);
    expect(all.any((item) => item.isGlobal), isTrue);

    final found = await api.gallery(search: 'polévka');
    expect(found, isNotEmpty);
  });
}
