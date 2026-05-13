import 'package:dio/dio.dart';

import 'api_response.dart';

class ItflowClient {
  final Dio _dio;
  final String baseUrl;
  final String apiKey;
  final String? decryptPassword;

  ItflowClient({
    required this.baseUrl,
    required this.apiKey,
    this.decryptPassword,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = 'application/json';
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
    final qp = <String, dynamic>{
      'api_key': apiKey,
      if (query != null) ...query,
    };
    if (includeDecrypt && decryptPassword != null) {
      qp['api_key_decrypt_password'] = decryptPassword;
    }
    try {
      final resp = await _dio.get(
        _join(module, action),
        queryParameters: qp,
        options: Options(responseType: ResponseType.json),
      );
      return _parse(resp);
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
    if (sc == 401) return 'Unauthorized — check your API key.';
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
