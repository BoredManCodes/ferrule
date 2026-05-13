class ApiResponse {
  final bool success;
  final String? message;
  final int? count;
  final dynamic data;

  ApiResponse({
    required this.success,
    this.message,
    this.count,
    this.data,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['success'];
    final ok = raw == true || raw == 'True' || raw == 'true' || raw == 1;
    return ApiResponse(
      success: ok,
      message: json['message']?.toString(),
      count: json['count'] is int
          ? json['count'] as int
          : int.tryParse(json['count']?.toString() ?? ''),
      data: json['data'],
    );
  }

  List<Map<String, dynamic>> get rows {
    final d = data;
    if (d is List) {
      return d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Map<String, dynamic>? get row {
    final d = data;
    if (d is List && d.isNotEmpty) {
      return Map<String, dynamic>.from(d.first as Map);
    }
    if (d is Map) return Map<String, dynamic>.from(d);
    return null;
  }

  /// Extracts `insert_id` from a create endpoint response.
  int? get insertId {
    final r = row;
    if (r == null) return null;
    final v = r['insert_id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => 'ApiException($statusCode): $message';
}
