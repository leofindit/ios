// lib/main.dart

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

  int _scanSession = 0;
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

  // Toggle BLE scanning on/off
  Future<void> toggleScan() async {
    if (scanning) {
      // invalidate any pending auto-stop task
      _scanSession++;

      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;

      if (!mounted) return;
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
      });
      return;
    }

    // starting a new session
    final mySession = ++_scanSession;

    // Auto-stop logic
    unawaited(() async {
      try {
        await BleBridge.startScan(); // start immediately
      } catch (_) {
        if (!mounted || _scanSession != mySession) return;

        await _motionSub?.cancel();
        _motionSub = null;

        setState(() {
          scanning = false;
          lastScanTime = DateTime.now();
        });
        return;
      }

      // mark scanning=true after startScan succeeds
      if (!mounted || _scanSession != mySession) return;
      setState(() => scanning = true);
      _startMotionDetection();

      // Auto-stop after 5 min (but cancel-safe)
      await Future.delayed(const Duration(minutes: 5));
      if (!mounted || _scanSession != mySession) return;

      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;

      if (!mounted || _scanSession != mySession) return;
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
      });
    }());
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
    const double maxDistanceM = 20.0; // Advanced view
    const double nearDistanceM = 5.0; // Main list

    // 1) Build an “advanced list” (<= 50m)
    // Keep UNKNOWN + APPLE_DEVICE so you don’t miss AirTag-ish packets on iOS.
    final advancedDevices =
        devices
            .where((d) => d.distanceMeters <= maxDistanceM)
            .where(
              (d) =>
                  d.isLikelyTile ||
                  d.isLikelySamsung ||
                  d.isLikelyAirTag ||
                  d.kind == "APPLE_DEVICE" ||
                  d.kind == "UNKNOWN",
            )
            .toList()
          ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    // 2) Near list for the main Scan page (<= 15m)
    final nearDevices = advancedDevices
        .where((d) => d.distanceMeters <= nearDistanceM)
        .where(
          (d) =>
              d.isLikelyTile ||
              d.isLikelySamsung ||
              d.isLikelyAirTag ||
              d.kind == "APPLE_DEVICE",
        )
        .toList();

    // 3) Pages
    final pages = [
      DistancePage(
        nearDevices: nearDevices,
        allTrackedDevices:
            advancedDevices, // 50m list in Show All Devices button
        scanning: scanning,
        onRescan: toggleScan,
        lastScanTime: lastScanTime,
      ),
      IdentificationPage(devices: advancedDevices),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/leo_splash.png',
                      height: 30,
                      width: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LEOFindIt',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.grey,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ),

          body: SafeArea(bottom: false, child: pages[pageIndex]),
          bottomNavigationBar: SafeArea(
            top: false,
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
