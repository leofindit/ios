import 'dart:async';
import 'package:flutter/services.dart';
import 'models.dart';

class BleBridge {
  static const MethodChannel _ch = MethodChannel("leo_find_it/scanner");

  static final _controller = StreamController<TrackerDevice>.broadcast();
  static bool _attached = false;

  static Stream<TrackerDevice> get detections => _controller.stream;

  static void _attachOnce() {
    if (_attached) return;
    _attached = true;

    _ch.setMethodCallHandler((call) async {
      if (call.method == "onDevice") {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _controller.add(TrackerDevice.fromNative(data));
      }
    });
  }

  static Future<void> startScan({int? durationMs, Duration? duration}) async {
    _attachOnce();
    await _ch.invokeMethod("startScan");

    // Only auto-stop if a duration is explicitly provided.
    if (durationMs != null || duration != null) {
      final wait = duration ?? Duration(milliseconds: durationMs ?? 4000);
      await Future.delayed(wait);
      await stopScan();
    }
  }

  static Future<void> stopScan() async {
    try {
      await _ch.invokeMethod("stopScan");
    } catch (_) {}
  }
}
