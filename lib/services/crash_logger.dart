import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CrashLogger {
  static const _channel = MethodChannel('com.prplegryn.fourgcut/media');
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterError?.call(details);
      unawaited(record('flutter', details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record('platform', error, stack));
      // Mark it handled after persisting the crash details. This keeps the log
      // available instead of letting the engine terminate before the channel call.
      return true;
    };
  }

  static Future<void> record(String category, Object error, StackTrace? stack) async {
    final stackText = stack?.toString() ?? StackTrace.current.toString();
    await recordText(category, '$error\n$stackText');
  }

  static Future<void> recordText(String category, String details) async {
    try {
      await _channel.invokeMethod<void>('writeCrashLog', <String, String>{
        'category': category,
        'details': details,
      });
    } catch (_) {
      // Keep a last-resort app-local copy when the engine channel is unavailable.
      try {
        final directory = Directory('${Directory.systemTemp.path}/4GCut');
        await directory.create(recursive: true);
        final file = File('${directory.path}/crash.log');
        final line = jsonEncode(<String, String>{
          'time': DateTime.now().toIso8601String(),
          'category': category,
          'details': details,
        });
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {
        // A crash logger must never become the source of another crash.
      }
    }
  }
}
