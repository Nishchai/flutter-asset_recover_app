import '../../core/error/result.dart';

/// Interactor / UseCase pattern: each use case is a single, testable unit of
/// application business logic. Presentation depends on use cases, never on
/// repositories directly.
abstract class UseCase<Output, Params> {
  Future<Result<Output>> call(Params params);
}

/// Marker for use cases that take no arguments.
class NoParams {
  const NoParams();
}
