import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/errors/app_exception.dart';

/// Maps the self-hosted API's uniform error envelope
/// (`docs/BACKEND_API.md` §1) to [FinFlowException] subclasses so the UI can
/// surface a stable, user-facing message and never leak internals.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.requestId,
  });

  /// Machine-readable server code: VALIDATION_FAILED, UNAUTHORIZED, ….
  final String code;

  /// Human-readable message from the server (or a fallback).
  final String message;

  final int? statusCode;
  final String? requestId;

  /// Whether the access token is invalid/expired and a refresh + retry is
  /// the right recovery (401 with code UNAUTHORIZED).
  bool get isUnauthorized => statusCode == 401;

  /// Whether retrying after a refresh could succeed (network blips, 5xx).
  bool get isRetryable =>
      statusCode == null || statusCode! >= 500 || statusCode == 429;

  @override
  String toString() => message;

  /// Parses an error response body into [ApiException]. Falls back to a
  /// generic message when the body is not the documented envelope.
  factory ApiException.fromResponse(http.Response response) {
    final status = response.statusCode;
    final requestId = response.headers['x-request-id'];
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> &&
            error['code'] is String &&
            error['message'] is String) {
          return ApiException(
            code: error['code'] as String,
            message: error['message'] as String,
            statusCode: status,
            requestId: requestId,
          );
        }
      }
    } on FormatException {
      // Not JSON — fall through to the generic mapping.
    }
    return ApiException(
      code: 'HTTP_$status',
      message: _fallbackMessage(status),
      statusCode: status,
      requestId: requestId,
    );
  }

  /// Builds an [ApiException] for a transport-level failure (no response).
  factory ApiException.network(Object error) => ApiException(
    code: 'NETWORK',
    message: 'Could not reach the server. Check your connection and try again.',
  );

  static String _fallbackMessage(int status) => switch (status) {
    400 => 'The request was invalid.',
    401 => 'Your session has expired — sign in again.',
    403 => 'You do not have permission to do that.',
    404 => 'That resource was not found.',
    409 => 'The data changed on another device.',
    429 => 'Too many requests — try again in a moment.',
    _ => 'The server returned an unexpected error.',
  };

  /// Converts to a [FinFlowException] for the UI (keeps the message).
  FinFlowException toFinFlowException() {
    final code = this.code;
    if (code == 'UNAUTHORIZED') {
      return const ValidationException(
        'Your session has expired — please sign in again.',
      );
    }
    if (code == 'VALIDATION_FAILED') {
      return ValidationException(message);
    }
    if (code == 'CONFLICT' || code == 'LEDGER_IMBALANCE') {
      return DomainException(message);
    }
    if (code == 'NOT_FOUND') {
      return NotFoundException(message);
    }
    return DomainException(message);
  }
}
