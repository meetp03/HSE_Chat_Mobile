class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final int? statusCode;
  final Map<String, dynamic>? errors;

  const ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.statusCode,
    this.errors,
  });

  factory ApiResponse.success(T data, {String? message, int? statusCode}) {
    return ApiResponse(
      success: true,
      data: data,
      message: message,
      statusCode: statusCode,
    );
  }

  factory ApiResponse.error(
    String message, {
    int? statusCode,
    Map<String, dynamic>? errors,
  }) {
    return ApiResponse(
      success: false,
      message: message,
      statusCode: statusCode,
      errors: errors,
    );
  }

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) dataParser,
  ) {
    try {
      return ApiResponse(
        success: json['success'] ?? false,
        message: json['message'],
        data: json['data'] != null ? dataParser(json['data']) : null,
        statusCode: json['status_code'],
        errors: json['errors'],
      );
    } catch (e) {
      return ApiResponse.error('Failed to parse response');
    }
  }
}
