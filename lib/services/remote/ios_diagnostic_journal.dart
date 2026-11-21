import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded, durable, full-fidelity engineering events for the iOS test agent.
/// Data is held on device until an explicit diagnostic_export command uploads
/// selected byte ranges to the owner's Torriodb repository.
class IosDiagnosticJournal {
  IosDiagnosticJournal._({Directory? directory, bool testEnabled = false})
      : _testDirectory = directory,
        _testEnabled = testEnabled;

  static final IosDiagnosticJournal instance = IosDiagnosticJournal._();

  @visibleForTesting
  factory IosDiagnosticJournal.forTesting(Directory directory) =>
      IosDiagnosticJournal._(directory: directory, testEnabled: true);

  static const maxFileBytes = 12 * 1024 * 1024;
  static const maxCaptureBytes = 8 * 1024 * 1024;
  static const maxEventBytes = 10000;
  static const maxReadEvents = 30;
  static const maxExportBytes = 48 * 1024;

  final Directory? _testDirectory;
  final bool _testEnabled;
  bool enabled = false;
  Future<void> _tail = Future<void>.value();
  int _written = 0;
  int _failures = 0;
  int _fragmented = 0;
  DateTime? _lastWrite;

  bool get isEnabled => enabled || _testEnabled;

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<Directory> _directory() async {
    final base = _testDirectory ?? await getApplicationSupportDirectory();
    final target = _testDirectory ?? Directory(
        '${base.path}${Platform.pathSeparator}playtorrio_diagnostic_journal');
    if (!await target.exists()) await target.create(recursive: true);
    return target;
  }

  Future<File> _file(String segment) async {
    if (!const <String>{'current', 'previous', 'capture'}.contains(segment)) {
      throw const FormatException('Unsupported journal segment');
    }
    final dir = await _directory();
    final extension = segment == 'capture' ? 'png' : 'jsonl';
    return File('${dir.path}${Platform.pathSeparator}$segment.$extension');
  }

  Future<void> record(String kind, Map<String, Object?> details) async {
    if (!isEnabled || kind.isEmpty) return;
    try {
      final value = <String, Object?>{
        'utc': DateTime.now().toUtc().toIso8601String(),
        'kind': kind,
        'details': details,
      };
      final encoded = utf8.encode(jsonEncode(value));
      if (encoded.length > maxEventBytes) {
        // Fragment large native errors, HTTP responses, and property lists
        // rather than silently dropping their diagnostic details.
        _fragmented++;
        final id = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
        const partSize = 5000;
        final parts = (encoded.length / partSize).ceil();
        for (var i = 0; i < parts; i++) {
          final start = i * partSize;
          final end = min(start + partSize, encoded.length);
          final fragment = utf8.encode(jsonEncode(<String, Object?>{
            'utc': DateTime.now().toUtc().toIso8601String(),
            'kind': 'journal.event_fragment',
            'details': <String, Object?>{
              'eventId': id, 'originalKind': kind,
              'part': i, 'parts': parts, 'originalBytes': encoded.length,
              'dataBase64': base64Encode(encoded.sublist(start, end)),
            },
          }));
          await _append(fragment);
        }
      } else {
        await _append(encoded);
      }
    } catch (error) {
      _failures++;
      debugPrint('[IosDiagnosticJournal] Write failed: ${error.runtimeType}');
    }
  }

  Future<void> _append(List<int> encoded) => _synchronized(() async {
    final current = await _file('current');
    final oldSize = await current.exists() ? await current.length() : 0;
    if (oldSize + encoded.length + 1 > maxFileBytes) {
      final previous = await _file('previous');
      if (await previous.exists()) await previous.delete();
      if (await current.exists()) await current.rename(previous.path);
    }
    await current.writeAsBytes([...encoded, 10], mode: FileMode.append,
        flush: false);
    _written++;
    _lastWrite = DateTime.now().toUtc();
  });

  Future<Map<String, Object?>> saveCapture(List<int> bytes) async {
    if (!isEnabled || bytes.isEmpty || bytes.length > maxCaptureBytes) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_capture_size',
      };
    }
    try {
      return await _synchronized(() async {
        final file = await _file('capture');
        await file.writeAsBytes(bytes, flush: true);
        return <String, Object?>{
          'accepted': true, 'segment': 'capture',
          'bytes': bytes.length,
          'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
        };
      });
    } catch (error) {
      return <String, Object?>{
        'accepted': false, 'reason': 'capture_write_failed',
        'errorClass': error.runtimeType.toString(),
      };
    }
  }

  Future<Map<String, Object?>> status() => _synchronized(() async {
    final now = await _file('current');
    final old = await _file('previous');
    final capture = await _file('capture');
    return <String, Object?>{
      'accepted': true,
      'enabled': isEnabled,
      'written': _written,
      'writeFailures': _failures,
      'fragmentedEvents': _fragmented,
      'oversizedEvents': _fragmented,
      'lastWriteUtc': _lastWrite?.toIso8601String(),
      'currentBytes': await now.exists() ? await now.length() : 0,
      'previousBytes': await old.exists() ? await old.length() : 0,
      'captureBytes': await capture.exists() ? await capture.length() : 0,
    };
  });

  Future<Map<String, Object?>> tail({String segment = 'current',
      int count = 10}) => _synchronized(() async {
    if (segment == 'capture') {
      return <String, Object?>{
        'accepted': false, 'reason': 'capture_is_binary',
      };
    }
    if (count < 1 || count > maxReadEvents) {
      return <String, Object?>{'accepted': false, 'reason': 'invalid_count'};
    }
    final file = await _file(segment);
    if (!await file.exists()) {
      return <String, Object?>{
        'accepted': true, 'segment': segment, 'events': <Object>[],
      };
    }
    // The complete journal segment is at most 2 MB, but the receipt
    // includes only a bounded number of latest records.
    final data = await file.readAsLines();
    final results = <Object>[];
    var bytes = 0;
    for (final line in data.reversed) {
      if (results.length >= count) break;
      final length = utf8.encode(line).length;
      if (bytes + length > 6500) {
        if (results.isEmpty) {
          try {
            final large = jsonDecode(line);
            if (large is Map) {
              results.add(<String, Object?>{
                'kind': large['kind'],
                'utc': large['utc'],
                'truncatedInTail': true,
                'sizeBytes': length,
                'exportAvailable': true,
              });
            }
          } catch (_) {
            results.add({'kind': 'journal.invalid_json'});
          }
        }
        break;
      }
      try {
        results.add(jsonDecode(line) as Object);
        bytes += length;
      } catch (_) {
        results.add({'kind': 'journal.invalid_json'});
      }
    }
    return <String, Object?>{
      'accepted': true,
      'segment': segment,
      'events': results.reversed.toList(growable: false),
      'returned': results.length,
    };
  });

  /// Return a bounded raw byte slice. The caller can upload slices to distinct
  /// Torriodb keys and continue at nextOffset after a connection failure.
  Future<Map<String, Object?>> readChunk({
    String segment = 'current',
    int offset = 0,
    int length = maxExportBytes,
  }) => _synchronized(() async {
    if (offset < 0 || length < 1 || length > maxExportBytes) {
      return <String, Object?>{
        'accepted': false, 'reason': 'invalid_export_range',
      };
    }
    final file = await _file(segment);
    if (!await file.exists()) {
      return <String, Object?>{
        'accepted': false, 'reason': 'segment_missing',
      };
    }
    final size = await file.length();
    if (offset > size) {
      return <String, Object?>{
        'accepted': false, 'reason': 'offset_out_of_range',
        'size': size,
      };
    }
    final bytes = <int>[];
    final stream = file.openRead(offset, min(offset + length, size));
    await for (final part in stream) {
      bytes.addAll(part);
    }
    final next = offset + bytes.length;
    return <String, Object?>{
      'accepted': true,
      'segment': segment,
      'offset': offset,
      'nextOffset': next,
      'sizeAtRead': size,
      'complete': next >= size,
      'dataBase64': base64Encode(bytes),
      'bytes': bytes.length,
    };
  });
}
