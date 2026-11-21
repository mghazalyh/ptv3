import 'package:flutter/foundation.dart';

/// One app-wide queue for the private Torriodb Contents API branch.
///
/// Receipts, device heartbeats, Live TV matrix output, and iOS performance
/// telemetry all create commits against the same branch. Distinct paths can
/// still race during GitHub Contents API commits; serialize in-app writers.
/// Each caller receives its own success/failure without poisoning the queue.
class TorriodbWriteQueue {
  TorriodbWriteQueue();

  static final TorriodbWriteQueue instance = TorriodbWriteQueue();

  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final queued = _tail.then((_) => task());
    _tail = queued.then<void>((_) {}, onError: (
        Object error, StackTrace stackTrace) {
      // Never print URLs, request bodies, header values, or credentials.
      debugPrint('[TorriodbWriteQueue] Upload task failed: '
          '${error.runtimeType}');
    });
    return queued;
  }
}
