// ---------------------------
// leofindit_ios/lib/main.dart
// ---------------------------
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'ble_bridge.dart';
import 'models.dart';
import 'distance_page.dart';
import 'identification_page.dart';

void main() {
  runApp(const LeoTrackerApp());
}

class LeoTrackerApp extends StatefulWidget {
  const LeoTrackerApp({super.key});

  @override
  State<LeoTrackerApp> createState() => _LeoTrackerAppState();
}

class _LeoTrackerAppState extends State<LeoTrackerApp>
    with SingleTickerProviderStateMixin {
  final Map<String, TrackerDevice> _devicesBySig = {};

  bool scanning = false;
  int pageIndex = 0;
  DateTime? lastScanTime;

  StreamSubscription<TrackerDevice>? _bleSub;
  StreamSubscription<AccelerometerEvent>? _motionSub;

  double _lastMag = 0;
  final double _movementThreshold = 1.2;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _fadeCtrl.forward();

    _bleSub = BleBridge.detections.listen((device) {
      setState(() {
        final prev = _devicesBySig[device.signature];
        _devicesBySig[device.signature] = prev == null
            ? device
            : prev.merge(device);
      });
    });
  }

  // Stable ordering by first seen ms instead of last seen ms
  // This prevents cards from jumping as RSSI/distance updates.
  List<TrackerDevice> get devices =>
      _devicesBySig.values.toList()
        ..sort((a, b) => a.firstSeenMs.compareTo(b.firstSeenMs));

  Future<void> toggleScan() async {
    if (scanning) {
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;

      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
      });
    } else {
      await BleBridge.startScan();
      _startMotionDetection();

      setState(() {
        scanning = true;
      });
    }
  }

  void _startMotionDetection() {
    _motionSub = accelerometerEventStream().listen((event) {
      if (!scanning) return;

      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      final delta = (magnitude - _lastMag).abs();
      _lastMag = magnitude;

      if (delta > _movementThreshold) {
        // BLE scan already running continuously
      }
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _motionSub?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackedDevices = devices
        .where((d) => d.isLikelyAirTag || d.isLikelyTile)
        .toList();

    final pages = [
      DistancePage(
        devices: trackedDevices,
        scanning: scanning,
        onRescan: toggleScan,
        lastScanTime: lastScanTime,
      ),
      IdentificationPage(devices: trackedDevices),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FadeTransition(
        opacity: _fadeAnim,
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/leo_splash.png',
                      height: 20,
                      width: 20,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LEOFindIt',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: pages[pageIndex],
          bottomNavigationBar: SizedBox(
            height: 71,
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: pageIndex,
              selectedItemColor: Colors.blueAccent,
              unselectedItemColor: Colors.grey,
              selectedFontSize: 16,
              unselectedFontSize: 12,
              iconSize: 28,
              onTap: (i) => setState(() => pageIndex = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Scan'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.list_alt),
                  label: 'Identify',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
