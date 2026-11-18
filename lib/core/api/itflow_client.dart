import 'package:dio/dio.dart';

import 'api_response.dart';

class ItflowClient {
  final Dio _dio;
  final String baseUrl;
  final String apiKey;
  final String? decryptPassword;

  /// Newer ITFlow builds take the key in the `X-API-Key` header and can be
  /// set to refuse (and flag) keys sent in the address. Older builds only
  /// read `api_key` from the query string or JSON body. We start with the
  /// header and drop back to the query string for GETs once an old server
  /// answers 401 to it.
  bool _keyInQuery = false;

  ItflowClient({
    required this.baseUrl,
    required this.apiKey,
    this.decryptPassword,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = 'application/json'
      ..headers['X-API-Key'] = apiKey;
  }

  String _join(String module, String action) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$root/api/v1/$module/$action.php';
  }

  Future<ApiResponse> get(
    String module,
    String action, {
    Map<String, dynamic>? query,
    bool includeDecrypt = false,
  }) async {
    // The decrypt password goes in a JSON body even on GET: ITFlow reads it
    // from the body only, so it never lands in web server access logs.
    final body = (includeDecrypt && decryptPassword != null)
        ? <String, dynamic>{'api_key_decrypt_password': decryptPassword}
        : null;
    Future<Response> send() => _dio.get(
          _join(module, action),
          queryParameters: {
            if (_keyInQuery) 'api_key': apiKey,
            if (query != null) ...query,
          },
          data: body,
          options: Options(
            responseType: ResponseType.json,
            contentType: body != null ? 'application/json' : null,
          ),
        );
    try {
      try {
        return _parse(await send());
      } on DioException catch (e) {
        if (e.response?.statusCode == 401 && !_keyInQuery) {
          _keyInQuery = true;
          return _parse(await send());
        }
        rethrow;
      }
    } on DioException catch (e) {
      throw ApiException(_dioMessage(e), statusCode: e.response?.statusCode);
    }
  }

  Future<ApiResponse> post(
    String module,
    String action, {
    required Map<String, dynamic> body,
    bool includeDecrypt = false,
  }) async {
    // api_key in the JSON body works on every ITFlow version and isn't
    // logged like a query string.
    final payload = <String, dynamic>{
      'api_key': apiKey,
      ...body,
    };
    if (includeDecrypt && decryptPassword != null) {
      payload['api_key_decrypt_password'] = decryptPassword;
    }
    try {
      final resp = await _dio.post(
        _join(module, action),
        data: payload,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.json,
        ),
      );
      return _parse(resp);
    } on DioException catch (e) {
      throw ApiException(_dioMessage(e), statusCode: e.response?.statusCode);
    }
  }

  ApiResponse _parse(Response resp) {
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      return ApiResponse.fromJson(data);
    }
    if (data is String) {
      // Some PHP endpoints return non-JSON on certain errors
      return ApiResponse(success: false, message: data);
    }
    return ApiResponse(success: false, message: 'Unexpected response');
  }

  String _dioMessage(DioException e) {
    final sc = e.response?.statusCode;
    if (sc == 401) {
      final d = e.response?.data;
      final msg = d is Map ? d['message']?.toString() : null;
      return msg ?? 'Unauthorized — check your API key.';
    }
    if (sc == 403) {
      final d = e.response?.data;
      final msg = d is Map ? d['message']?.toString() : null;
      return msg ?? 'Forbidden — the API key\'s role can\'t do that.';
    }
    if (sc == 404) return 'Endpoint not found — check instance URL.';
    if (sc == 405) return 'Method not allowed.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Request timed out.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach instance. Verify URL and network.';
    }
    return e.message ?? 'Network error';
  }
}
