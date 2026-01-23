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

  static Future<void> startScan() async {
    _attachOnce();
    await _ch.invokeMethod("startScan");
  }

  static Future<void> stopScan() async {
    try {
      await _ch.invokeMethod("stopScan");
    } catch (_) {}
  }
}
