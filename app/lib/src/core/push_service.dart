import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_service.dart';

/// Zpráva z push notifikace přeložená do toho, co aplikace umí otevřít.
class PushTap {
  const PushTap({required this.type, this.proposalId, this.date});

  /// `proposal` nebo `comment` — podle toho, co notifikaci vyvolalo.
  final String type;
  final String? proposalId;

  /// Den jídla (YYYY-MM-DD). Bez něj detail otevřít nejde.
  final String? date;

  static PushTap? fromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type is! String) return null;
    return PushTap(
      type: type,
      proposalId: data['proposalId'] as String?,
      date: data['date'] as String?,
    );
  }
}

/// Push notifikace přes Firebase Cloud Messaging.
///
/// Celá třída je záměrně odolná vůči tomu, že Firebase není k dispozici —
/// na iOS zatím chybí konfigurace, v testech Firebase neběží vůbec a
/// backend nemusí mít nastavené FCM. Notifikace jsou doplněk, ne podmínka
/// fungování aplikace, takže se každá chyba jen zaloguje.
class PushService {
  PushService(this._api);

  final ApiService _api;

  /// Token posledního registrovaného zařízení — potřebný při odhlášení.
  String? _registeredToken;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  bool _initialized = false;

  /// Ťuknutí na notifikaci. Router na to naslouchá a otevře detail jídla.
  final _taps = StreamController<PushTap>.broadcast();
  Stream<PushTap> get taps => _taps.stream;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  /// Spustí se po přihlášení. Vyžádá povolení, získá token a ohlásí ho
  /// backendu. Volat opakovaně je bezpečné.
  Future<void> start() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
    } catch (err) {
      debugPrint('Firebase se nepodařilo spustit, push bude vypnutý: $err');
      return;
    }

    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // Na Androidu 13+ i na iOS je potřeba výslovné povolení uživatele.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Uživatel notifikace odmítl.');
        return;
      }

      await _registerCurrentToken(messaging);

      // FCM token se může kdykoli změnit — po obnovení ho pošleme znovu.
      _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((token) {
        _register(token).catchError(
          (Object err) => debugPrint('Obnovený token se nepodařilo ohlásit: $err'),
        );
      });

      // Ťuknutí na notifikaci, když aplikace běží na pozadí.
      _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

      // Aplikace byla notifikací teprve spuštěná.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpened(initial);
    } catch (err) {
      debugPrint('Nastavení push notifikací selhalo: $err');
    }
  }

  Future<void> _registerCurrentToken(FirebaseMessaging messaging) async {
    final token = await messaging.getToken();
    if (token == null) {
      debugPrint('FCM nevrátil token zařízení.');
      return;
    }
    await _register(token);
  }

  Future<void> _register(String token) async {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'web',
    };

    try {
      final result = await _api.registerDevice(token: token, platform: platform);
      _registeredToken = token;
      if (!result.pushEnabled) {
        // Backend nemá nastavené FCM — registrace proběhla, ale nic nedorazí.
        debugPrint('Server nemá zapnuté push notifikace.');
      }
    } on ApiException catch (e) {
      debugPrint('Registrace zařízení selhala: ${e.message}');
    }
  }

  void _handleOpened(RemoteMessage message) {
    final tap = PushTap.fromData(message.data);
    if (tap != null && !_taps.isClosed) _taps.add(tap);
  }

  /// Volá se při odhlášení — jinak by notifikace rodiny chodily i tomu,
  /// kdo se na sdíleném zařízení odhlásil.
  Future<void> stop() async {
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    _refreshSub = null;
    _openedSub = null;

    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;

    try {
      await _api.unregisterDevice(token);
    } on ApiException catch (e) {
      debugPrint('Odhlášení zařízení selhalo: ${e.message}');
    }
  }

  void dispose() {
    _refreshSub?.cancel();
    _openedSub?.cancel();
    _taps.close();
  }
}
