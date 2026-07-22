/// Domain-level error type. Use cases convert exceptions thrown by the data
/// layer into a [Failure] so the presentation layer never handles raw
/// exceptions. Part of the Result-based error-handling pattern.
sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// Backend / API error (non-2xx, parse error, etc.).
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error']);
}

/// Connectivity / timeout error.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network unavailable']);
}

/// Local cache / persistence error.
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Storage error']);
}

/// Input/validation error surfaced from the domain.
class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Invalid input']);
}

/// Anything not otherwise classified.
class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong']);
}
