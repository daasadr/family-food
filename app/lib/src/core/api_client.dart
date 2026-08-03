import 'dart:async';

import 'package:dio/dio.dart';

import 'token_storage.dart';

/// Chyba z API se stabilním kódem — UI podle něj rozlišuje případy.
class ApiException implements Exception {
  ApiException({required this.code, required this.message, this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNoFamily => code == 'NO_FAMILY';

  @override
  String toString() => message;
}

/// Volá se, když ani refresh token neprošel — aplikace má odhlásit uživatele.
typedef OnSessionExpired = Future<void> Function();

class ApiClient {
  ApiClient({required String baseUrl, required TokenStorage storage})
      : _storage = storage,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            contentType: 'application/json',
            // Chyby řešíme sami v _toApiException, ne přes výjimky Dia.
            validateStatus: (status) => status != null && status < 500,
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['skipAuth'] != true) {
            final token = await _storage.readAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStorage _storage;

  OnSessionExpired? onSessionExpired;

  /// Aby souběžné 401 nespustily několik refreshů naráz.
  Future<bool>? _refreshInFlight;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _request<T>(() => _dio.get(path, queryParameters: query));

  /// U akcí bez vstupu (hlasování, potvrzení, …) posíláme prázdný objekt —
  /// hlavička content-type: application/json bez těla je pro server chyba.
  Future<T> post<T>(String path, {Object? body, bool skipAuth = false}) =>
      _request<T>(() => _dio.post(
            path,
            data: body ?? const <String, dynamic>{},
            options: Options(extra: {'skipAuth': skipAuth}),
          ));

  Future<T> patch<T>(String path, {Object? body}) =>
      _request<T>(() => _dio.patch(path, data: body));

  Future<T> put<T>(String path, {Object? body}) =>
      _request<T>(() => _dio.put(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) =>
      _request<T>(() => _dio.delete(path, data: body));

  Future<T> _request<T>(Future<Response<dynamic>> Function() send) async {
    Response<dynamic> response;
    try {
      response = await send();
    } on DioException catch (e) {
      throw ApiException(
        code: 'NETWORK_ERROR',
        message: _networkMessage(e),
      );
    }

    if (response.statusCode == 401 && await _tryRefresh()) {
      try {
        response = await send();
      } on DioException catch (e) {
        throw ApiException(code: 'NETWORK_ERROR', message: _networkMessage(e));
      }
    }

    final status = response.statusCode ?? 500;
    if (status >= 400) {
      if (status == 401) {
        await onSessionExpired?.call();
      }
      throw _toApiException(response);
    }

    return response.data as T;
  }

  ApiException _toApiException(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return ApiException(
        code: data['error'] as String? ?? 'UNKNOWN_ERROR',
        message: data['message'] as String? ?? 'Něco se nepovedlo.',
        statusCode: response.statusCode,
      );
    }
    return ApiException(
      code: 'UNKNOWN_ERROR',
      message: 'Server vrátil neočekávanou odpověď.',
      statusCode: response.statusCode,
    );
  }

  String _networkMessage(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Server neodpovídá. Zkus to prosím znovu.',
        DioExceptionType.connectionError =>
          'Nedaří se spojit se serverem. Zkontroluj připojení k internetu.',
        _ => 'Při komunikaci se serverem došlo k chybě.',
      };

  Future<bool> _tryRefresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      if (response.statusCode != 200) return false;

      final tokens = (response.data as Map<String, dynamic>)['tokens']
          as Map<String, dynamic>;
      await _storage.saveTokens(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
      );
      return true;
    } on DioException {
      return false;
    }
  }
}
