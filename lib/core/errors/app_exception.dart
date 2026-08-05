/// Base class for every exception raised by the FinFlow domain and
/// infrastructure layers.
///
/// All errors surfaced to the UI (snackbars, error states) should be
/// instances of [FinFlowException] so that user-facing messages stay
/// consistent and internals are never leaked.
sealed class FinFlowException implements Exception {
  const FinFlowException(this.message);

  /// A human-readable, user-facing description of the problem.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when user-supplied input fails validation rules.
class ValidationException extends FinFlowException {
  const ValidationException(super.message);
}

/// Thrown when an operation would violate a business / accounting rule
/// (for example, deleting an account that still holds ledger entries).
class DomainException extends FinFlowException {
  const DomainException(super.message);
}

/// Thrown when an expected entity (account, transaction, ...) does not
/// exist in the local database.
class NotFoundException extends FinFlowException {
  const NotFoundException(super.message);
}

/// Thrown when a storage layer operation fails unexpectedly.
class DatabaseException extends FinFlowException {
  const DatabaseException(super.message);
}
