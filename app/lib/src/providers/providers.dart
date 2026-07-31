import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_service.dart';
import '../core/date_utils.dart';
import '../core/token_storage.dart';
import '../models/models.dart';

/// Adresa API. Emulátor Androidu vidí hostitele jako 10.0.2.2.
/// Přepiš přes `flutter run --dart-define=API_BASE_URL=https://…`.
const String _defaultBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

String resolveBaseUrl() {
  if (_defaultBaseUrl.isNotEmpty) return _defaultBaseUrl;
  if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
    return 'http://10.0.2.2:3000/api/v1';
  }
  return 'http://localhost:3000/api/v1';
}

final tokenStorageProvider =
    Provider<TokenStorage>((ref) => SecureTokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: resolveBaseUrl(),
    storage: ref.watch(tokenStorageProvider),
  );
  client.onSessionExpired = () async {
    await ref.read(authProvider.notifier).forceLogout();
  };
  return client;
});

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(apiClientProvider)),
);

// --- Autentizace --------------------------------------------------------

sealed class AuthState {
  const AuthState();
}

/// Než se zjistí, jestli je v úložišti platná relace.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class Authenticated extends AuthState {
  const Authenticated(this.user);

  final AppUser user;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restoreSession);
    return const AuthLoading();
  }

  ApiService get _api => ref.read(apiServiceProvider);
  TokenStorage get _storage => ref.read(tokenStorageProvider);

  Future<void> _restoreSession() async {
    final token = await _storage.readAccessToken();
    if (token == null) {
      state = const Unauthenticated();
      return;
    }
    try {
      state = Authenticated(await _api.me());
    } on ApiException {
      await _storage.clear();
      state = const Unauthenticated();
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final result =
        await _api.register(email: email, password: password, name: name);
    await _storage.saveTokens(
      accessToken: result.tokens.accessToken,
      refreshToken: result.tokens.refreshToken,
    );
    state = Authenticated(result.user);
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _api.login(email: email, password: password);
    await _storage.saveTokens(
      accessToken: result.tokens.accessToken,
      refreshToken: result.tokens.refreshToken,
    );
    state = Authenticated(result.user);
  }

  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken);
      } on ApiException {
        // Odhlášení lokálně proběhne i tak.
      }
    }
    await forceLogout();
  }

  /// Vyhozeno serverem (vypršela relace) — jen uklidit lokální stav.
  Future<void> forceLogout() async {
    await _storage.clear();
    ref.invalidate(familyProvider);
    state = const Unauthenticated();
  }

  /// Po vstupu do rodiny se mění familyId v tokenu — je potřeba ho vyměnit.
  Future<void> applyNewTokens(AuthTokens tokens) async {
    await _storage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    state = Authenticated(await _api.me());
  }

  Future<void> createFamily(String name) async {
    final result = await _api.createFamily(name);
    await applyNewTokens(result.tokens);
    ref.invalidate(familyProvider);
  }

  Future<void> acceptInvite(String code) async {
    final result = await _api.acceptInvite(code);
    await applyNewTokens(result.tokens);
    ref.invalidate(familyProvider);
  }

  Future<void> leaveFamily() async {
    final tokens = await _api.leaveFamily();
    await applyNewTokens(tokens);
    ref.invalidate(familyProvider);
  }
}

final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Přihlášený uživatel, nebo null.
final currentUserProvider = Provider<AppUser?>((ref) {
  final state = ref.watch(authProvider);
  return state is Authenticated ? state.user : null;
});

// --- Rodina -------------------------------------------------------------

final familyProvider = FutureProvider<Family>(
  (ref) => ref.watch(apiServiceProvider).getFamily(),
);

final invitesProvider = FutureProvider<List<Invite>>(
  (ref) => ref.watch(apiServiceProvider).listInvites(),
);

// --- Šablona ------------------------------------------------------------

final templateProvider = FutureProvider<MealTemplate>(
  (ref) => ref.watch(apiServiceProvider).getTemplate(),
);

// --- Plánovač -----------------------------------------------------------

/// Pondělí právě zobrazeného týdne.
class SelectedWeekNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => startOfWeek(today());

  void shift(int weeks) => state = state.add(Duration(days: 7 * weeks));

  void goTo(DateTime date) => state = startOfWeek(date);

  void goToToday() => state = startOfWeek(today());
}

final selectedWeekProvider =
    NotifierProvider<SelectedWeekNotifier, DateTime>(SelectedWeekNotifier.new);

final weekPlanProvider = FutureProvider.family<WeekPlan, DateTime>(
  (ref, weekStart) =>
      ref.watch(apiServiceProvider).getWeek(apiDate(weekStart)),
);

final dayPlanProvider = FutureProvider.family<DayPlan, String>(
  (ref, date) => ref.watch(apiServiceProvider).getDay(date),
);

final commentsProvider = FutureProvider.family<List<MealComment>, String>(
  (ref, proposalId) =>
      ref.watch(apiServiceProvider).listComments(proposalId),
);

final galleryProvider = FutureProvider.family<List<GalleryItem>, String>(
  (ref, search) => ref.watch(apiServiceProvider).gallery(search: search),
);
