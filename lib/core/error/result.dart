import 'failure.dart';

/// Functional result type (an `Either<Failure, T>`). Use cases return this so
/// callers handle success and failure explicitly via [fold] — no try/catch in
/// the presentation layer.
sealed class Result<T> {
  const Result();

  /// Wraps a throwing computation into a [Result], mapping any error to
  /// [onError] (defaults to [UnknownFailure]).
  static Future<Result<T>> guard<T>(
    Future<T> Function() body, {
    Failure Function(Object error)? onError,
  }) async {
    try {
      return Ok<T>(await body());
    } catch (e) {
      return Err<T>(onError?.call(e) ?? UnknownFailure(e.toString()));
    }
  }
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

extension ResultX<T> on Result<T> {
  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  /// Collapses both branches into a single value.
  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };
}
