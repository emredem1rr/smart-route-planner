import 'dart:async';

/// Singleton that keeps long-running Futures alive regardless of widget lifecycle.
/// Screens use [run] to start or join an in-flight task; [waitFor] returns the
/// existing Future if one is already running for that key.
class BackgroundTaskService {
  static final BackgroundTaskService _i = BackgroundTaskService._();
  factory BackgroundTaskService() => _i;
  BackgroundTaskService._();

  final _active  = <String, Future<dynamic>>{};
  final _results = <String, dynamic>{};
  final _errors  = <String, dynamic>{};

  bool    isRunning(String key)  => _active.containsKey(key);
  bool    hasResult(String key)  => _results.containsKey(key);
  T?      result<T>(String key)  => _results[key] as T?;
  dynamic error(String key)      => _errors[key];

  /// Start [fn] under [key], or return the existing Future if already running.
  Future<T?> run<T>(String key, Future<T> Function() fn) {
    if (_active.containsKey(key)) return _active[key]! as Future<T?>;
    _results.remove(key);
    _errors.remove(key);
    final f = fn().then<T?>((r) {
      _results[key] = r;
      _active.remove(key);
      return r;
    }, onError: (e) {
      _errors[key] = e;
      _active.remove(key);
      return null;
    });
    _active[key] = f;
    return f;
  }

  /// Returns the in-flight Future for [key], or null if nothing is running.
  Future<T?>? waitFor<T>(String key) =>
      _active.containsKey(key) ? _active[key]! as Future<T?> : null;

  void clear(String key) {
    _active.remove(key);
    _results.remove(key);
    _errors.remove(key);
  }
}
