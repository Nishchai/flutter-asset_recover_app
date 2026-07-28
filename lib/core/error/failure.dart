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

/// Maps a thrown data-layer error onto a [Failure] whose [Failure.message] is
/// fit to show a user, keeping any human-readable text the backend supplied
/// (e.g. the `reason` field of a failed `commonLogin`).
///
/// `Result.guard`'s default is `UnknownFailure(e.toString())`, which leaks
/// Dart's `Type(...)` / `Type: ...` wrapper into the UI — pass this as
/// `onError` wherever the message is actually displayed.
Failure failureFrom(Object error) {
  final raw = switch (error) {
    StateError() => error.message,
    FormatException() => error.message,
    _ => error.toString(),
  };
  // `ApiException(Mobile not registered)` → `Mobile not registered`
  final wrapped = RegExp(r'^\w+\((.*)\)$', dotAll: true).firstMatch(raw);
  var message = wrapped?.group(1) ?? raw;
  // `Exception: Mobile not registered` → `Mobile not registered`
  final prefixed =
      RegExp(r'^\w*(?:Exception|Error):\s*(.*)$', dotAll: true).firstMatch(message);
  message = (prefixed?.group(1) ?? message).trim();
  return message.isEmpty ? const UnknownFailure() : ServerFailure(message);
}
