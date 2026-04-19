import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'ble_bridge.dart';
import 'models.dart';
import 'distance_page.dart';
import 'identification_page.dart';
import 'device_marks.dart';
import 'app_drawer.dart';
import 'filters.dart';
import 'reports_store.dart';
import 'search_page.dart';
import 'app_tutorial.dart';

void main() {
  runApp(const LeoTrackerApp());
}

class LeoTrackerApp extends StatefulWidget {
  const LeoTrackerApp({super.key});

  @override
  State<LeoTrackerApp> createState() => _LeoTrackerAppState();
}

class _LeoTrackerAppState extends State<LeoTrackerApp>
    with TickerProviderStateMixin {
  final Map<String, TrackerDevice> _devicesBySig = {};
  final Map<String, double> _heldPeakRssi = {};
  final Map<String, int> _heldPeakUntilMs = {};

  static const int _freshPriorityWindowMs = 15 * 1000;

  bool scanning = false;
  int pageIndex = 0;
  DateTime? lastScanTime;
  DateTime? scanStartTime;

  StreamSubscription<TrackerDevice>? _bleSub;
  StreamSubscription<AccelerometerEvent>? _motionSub;

  double _lastMag = 0;
  final double _movementThreshold = 1.2;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _blinkCtrl;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey _scanButtonKey = GlobalKey();
  final GlobalKey _trackerListKey = GlobalKey();
  final GlobalKey _firstTrackerCardKey = GlobalKey();
  final GlobalKey _identifyTabsKey = GlobalKey();
  final GlobalKey _drawerFiltersKey = GlobalKey();
  final GlobalKey _drawerReportsKey = GlobalKey();
  final GlobalKey _drawerQuickStartKey = GlobalKey();
  final GlobalKey _drawerGuidanceKey = GlobalKey();
  final GlobalKey _drawerAdvancedKey = GlobalKey();

  BuildContext? _materialContext;
  bool _tutorialRunning = false;
  bool _tutorialClosedEarly = false;
  bool _missionChosenThisLaunch = false;

  TrackerDevice get _demoTutorialDevice {
    final now = DateTime.now().millisecondsSinceEpoch;
    return TrackerDevice(
      signature: 'tutorial-demo-airtag',
      id: 'tutorial-demo-airtag',
      logicalId: 'tutorial-demo-airtag',
      kind: 'AIRTAG',
      pinnedMac: 'D4:90:F6:D4:4B:4F',
      lastMac: 'D4:90:F6:D4:4B:4F',
      rssi: -61,
      distanceMeters: 1.95,
      firstSeenMs: now - 6000,
      lastSeenMs: now - 1200,
      sightings: 8,
      rotatingMacCount: 1,
      rawFrame: '1EFF4C00121900112233445566778899AABBCC',
      smoothedRssi: -61,
      smoothedDistanceMeters: 1.95,
      status: DeviceStatus.undesignated,
    );
  }

  @override
  void initState() {
    super.initState();

    ReportsStore.init();
    DeviceMarks.init();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _fadeCtrl.forward();

    _bleSub = BleBridge.detections.listen((device) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      await DeviceMarks.restoreUndesignated(device.stableKey);

      setState(() {
        final prev = _devicesBySig[device.signature];
        _devicesBySig[device.signature] = prev == null
            ? device
            : prev.merge(device);

        _heldPeakRssi[device.signature] = max(
          _heldPeakRssi[device.signature] ?? device.smoothedRssi,
          device.smoothedRssi,
        );
        _heldPeakUntilMs[device.signature] = now + 10000;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      _checkFirstLaunchTutorial();
    });
  }

  List<TrackerDevice> get devices {
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final sig in _heldPeakUntilMs.keys.toList()) {
      if ((_heldPeakUntilMs[sig] ?? 0) < now) {
        _heldPeakRssi.remove(sig);
        _heldPeakUntilMs.remove(sig);
      }
    }

    final list = _devicesBySig.values.toList();

    if (FiltersModel.state.sortMode == SortMode.distanceAsc) {
      list.sort((a, b) {
        final aFresh = (now - a.lastSeenMs) <= _freshPriorityWindowMs;
        final bFresh = (now - b.lastSeenMs) <= _freshPriorityWindowMs;

        if (aFresh != bFresh) return aFresh ? -1 : 1;

        final recentGap = (a.lastSeenMs - b.lastSeenMs).abs();
        if (recentGap > 5000) {
          return b.lastSeenMs.compareTo(a.lastSeenMs);
        }

        final c = a.distanceMeters.compareTo(b.distanceMeters);
        if (c != 0) return c;

        return b.lastSeenMs.compareTo(a.lastSeenMs);
      });
      return list;
    }

    list.sort((a, b) {
      final aFresh = (now - a.lastSeenMs) <= _freshPriorityWindowMs;
      final bFresh = (now - b.lastSeenMs) <= _freshPriorityWindowMs;

      if (aFresh != bFresh) return aFresh ? -1 : 1;

      final recentGap = (a.lastSeenMs - b.lastSeenMs).abs();
      if (recentGap > 5000) {
        return b.lastSeenMs.compareTo(a.lastSeenMs);
      }

      final ar = _heldPeakRssi[a.signature] ?? a.smoothedRssi;
      final br = _heldPeakRssi[b.signature] ?? b.smoothedRssi;
      final c = br.compareTo(ar);
      if (c != 0) return c;

      return b.lastSeenMs.compareTo(a.lastSeenMs);
    });

    return list;
  }

  Future<void> toggleScan() async {
    if (_tutorialRunning) return;

    if (scanning) {
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;
      _blinkCtrl.stop();

      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
    } else {
      await BleBridge.startScan();
      _startMotionDetection();
      _blinkCtrl.repeat(reverse: true);

      setState(() {
        scanning = true;
        scanStartTime = DateTime.now();
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
        // Continuous BLE scan already active.
      }
    });
  }

  Future<void> _checkFirstLaunchTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_quick_start_guide') ?? false;

    if (!mounted) return;
    if (_materialContext == null) return;

    setState(() {
      _missionChosenThisLaunch = false;
    });

    if (seen) {
      await _showMissionPrompt();
      return;
    }

    await _showTutorialStartPrompt();
  }

  Future<void> _markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_quick_start_guide', true);
  }

  void _closeEntireTutorial() {
    _tutorialClosedEarly = true;
    if (_navigatorKey.currentState != null) {
      _navigatorKey.currentState!.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _showTutorialStartPrompt() async {
    final dialogContext = _materialContext;
    if (dialogContext == null) return;

    await showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Quick Start Guide',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Would you like a quickstart walkthrough of the app?',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _markTutorialSeen();
                if (_navigatorKey.currentState != null) {
                  _navigatorKey.currentState!.pop();
                }
                await _showMissionPrompt();
              },
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_navigatorKey.currentState != null) {
                  _navigatorKey.currentState!.pop();
                }
                await Future.delayed(const Duration(milliseconds: 250));
                await _markTutorialSeen();
                await _startQuickGuide();
                await _showMissionPrompt();
              },
              child: const Text('Start Guide'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMissionPrompt() async {
    final ctx = _materialContext;
    if (ctx == null || !mounted) return;

    await showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text(
          'Package mission / search mission',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _missionCard(
                title: 'Sealed package search',
                body:
                    'I\'m determining if there is a tag inside of a sealed package. Metal safe, cardboard, plastic, or another confined item.',
                onTap: () {
                  FiltersModel.applyMissionPreset(MissionMode.packageSearch);
                  if (mounted) {
                    setState(() {
                      _missionChosenThisLaunch = true;
                    });
                  }
                  Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: 10),
              _missionCard(
                title: 'Known-area tag hunt',
                body:
                    'I\'m hunting for a possible tag in a known area such as a vehicle or backpack.',
                onTap: () {
                  FiltersModel.applyMissionPreset(
                    MissionMode.wideAreaHiddenTag,
                  );
                  if (mounted) {
                    setState(() {
                      _missionChosenThisLaunch = true;
                    });
                  }
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missionCard({
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _showCoach(List<TargetFocus> targets) async {
    final coachContext = _materialContext;
    if (coachContext == null || targets.isEmpty) return false;

    final completer = Completer<bool>();

    final coach = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.78,
      paddingFocus: 10,
      hideSkip: true,
      onFinish: () {
        if (!completer.isCompleted) completer.complete(true);
      },
      onSkip: () {
        if (!completer.isCompleted) completer.complete(false);
        return true;
      },
    );

    await Future.delayed(const Duration(milliseconds: 100));
    coach.show(context: coachContext);
    return completer.future;
  }

  Future<void> _startQuickGuide() async {
    if (_tutorialRunning || !mounted) return;
    _tutorialRunning = true;
    _tutorialClosedEarly = false;

    if (scanning) {
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;
      _blinkCtrl.stop();
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
    }

    setState(() => pageIndex = 0);
    await Future.delayed(const Duration(milliseconds: 900));

    await _runDistanceTutorial();
    if (!mounted || _tutorialClosedEarly) {
      _tutorialRunning = false;
      return;
    }

    await _openSearchTutorialFromDemoTracker();
    if (!mounted || _tutorialClosedEarly) {
      _tutorialRunning = false;
      return;
    }

    setState(() => pageIndex = 1);
    await Future.delayed(const Duration(milliseconds: 900));

    await _runIdentifyTutorial();
    if (!mounted || _tutorialClosedEarly) {
      _tutorialRunning = false;
      return;
    }

    await _runDrawerTutorial();
    if (!mounted || _tutorialClosedEarly) {
      _tutorialRunning = false;
      return;
    }

    setState(() => pageIndex = 0);
    _tutorialRunning = false;
  }

  Future<void> _runDistanceTutorial() async {
    await _showCoach([
      tutorialTarget(
        key: _scanButtonKey,
        id: 'scan_button',
        title: 'Start and stop scanning',
        body: 'Press Scan here to stop and start device scanning.',
        showSkip: false,
      ),
      tutorialTarget(
        key: _trackerListKey,
        id: 'distance_list',
        title: 'Detected tags',
        body:
            'Undesignated tags show here with signal strength, UUID/MAC preview, and distance.',
        yOffset: 110,
        showSkip: false,
      ),
      tutorialTarget(
        key: _firstTrackerCardKey,
        id: 'open_tracker',
        title: 'Open a tag',
        body: 'Tap a tag to open the detailed search page.',
        showSkip: false,
      ),
    ]);
  }

  Future<void> _openSearchTutorialFromDemoTracker() async {
    final navContext = _materialContext;
    if (navContext == null || _tutorialClosedEarly) return;

    await Future.delayed(const Duration(milliseconds: 250));

    await Navigator.push(
      navContext,
      MaterialPageRoute(
        builder: (_) =>
            SearchPage(device: _demoTutorialDevice, tutorialMode: true),
      ),
    );
  }

  Future<void> _runIdentifyTutorial() async {
    await _showCoach([
      tutorialTarget(
        key: _identifyTabsKey,
        id: 'identify_tabs',
        title: 'Classified tags',
        body:
            'Tags can be moved into undesignated, friendly, nonsuspect, or suspect.',
        showSkip: false,
      ),
    ]);
  }

  Future<void> _runDrawerTutorial() async {
    _scaffoldKey.currentState?.openDrawer();
    await Future.delayed(const Duration(milliseconds: 600));

    await _showCoach([
      tutorialTarget(
        key: _drawerQuickStartKey,
        id: 'drawer_quick_start',
        title: 'Quick Start',
        body: 'Use this to rerun the tutorial any time.',
        showSkip: false,
      ),
      tutorialTarget(
        key: _drawerGuidanceKey,
        id: 'drawer_guidance',
        title: 'LEO Guidance',
        body: 'Open law-enforcement guidance here.',
        showSkip: false,
      ),
      tutorialTarget(
        key: _drawerFiltersKey,
        id: 'drawer_filters',
        title: 'Filters',
        body: 'Use filters to control search behavior.',
        showSkip: false,
      ),
      tutorialTarget(
        key: _drawerReportsKey,
        id: 'drawer_reports',
        title: 'Reports page',
        body: 'Saved suspect or found reports show up here.',
        showSkip: false,
      ),
      tutorialTarget(
        key: _drawerAdvancedKey,
        id: 'drawer_advanced',
        title: 'Advanced Features',
        body: 'Use this area for clearing saved tag designations.',
        showSkip: false,
      ),
    ]);

    if (!mounted || _materialContext == null || _tutorialClosedEarly) return;
    Navigator.of(_materialContext!).pop();
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _blinkCtrl.dispose();
    _motionSub?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackedDevices = devices
        .where(
          (d) =>
              d.isLikelyAirTag ||
              d.isLikelyFindMy ||
              d.isLikelyTile ||
              d.isLikelySamsung,
        )
        .toList();

    final tutorialTrackedDevices = _tutorialRunning
        ? <TrackerDevice>[_demoTutorialDevice]
        : trackedDevices;

    final missionLabel = !_missionChosenThisLaunch
        ? 'Select mission'
        : FiltersModel.state.missionMode == MissionMode.packageSearch
        ? 'Package mission'
        : 'Known-area hunt';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LeoFindIt',
      navigatorKey: _navigatorKey,
      home: Builder(
        builder: (materialContext) {
          _materialContext = materialContext;

          final pages = [
            DistancePage(
              devices: trackedDevices,
              scanning: scanning,
              onRescan: toggleScan,
              lastScanTime: lastScanTime,
              scanStartTime: scanStartTime,
              scanButtonKey: _scanButtonKey,
              trackerListKey: _trackerListKey,
              firstTrackerCardKey: _firstTrackerCardKey,
              tutorialMode: _tutorialRunning,
              tutorialDevice: _demoTutorialDevice,
            ),
            IdentificationPage(
              devices: tutorialTrackedDevices,
              identifyTabsKey: _identifyTabsKey,
            ),
          ];

          return FadeTransition(
            opacity: _fadeAnim,
            child: Scaffold(
              key: _scaffoldKey,
              drawer: AppDrawer(
                quickStartTileKey: _drawerQuickStartKey,
                guidanceTileKey: _drawerGuidanceKey,
                filtersTileKey: _drawerFiltersKey,
                reportsTileKey: _drawerReportsKey,
                advancedTileKey: _drawerAdvancedKey,
                onQuickStart: _startQuickGuide,
              ),
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.menu, size: 30),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                centerTitle: true,
                title: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
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
                      if (scanning)
                        FadeTransition(
                          opacity: _blinkCtrl,
                          child: const Icon(
                            Icons.circle,
                            color: Colors.redAccent,
                            size: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              body: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    color: const Color(0xFFF6F5F8),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFD8D4DE)),
                          ),
                          child: Text(
                            missionLabel,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5A5562),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: scanning
                                ? const Color(0xFFE8F5E9)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: scanning
                                  ? const Color(0xFF81C784)
                                  : const Color(0xFFD8D4DE),
                            ),
                          ),
                          child: Text(
                            scanning ? 'Scanning active' : 'Scan stopped',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: scanning
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF5A5562),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: pages[pageIndex]),
                ],
              ),
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
                    BottomNavigationBarItem(
                      icon: Icon(Icons.radar),
                      label: 'Scan',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.list_alt),
                      label: 'Classified Tags',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
