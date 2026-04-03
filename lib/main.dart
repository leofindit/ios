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

// Initialize the app and manage the overall state
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceMarks.init();
  await ReportsStore.init();
  runApp(const LeoTrackerApp());
}

// The LeoTrackerApp widget uses a StatefulWidget to maintain and update the state as the user interacts with the app and as new devices are detected through BLE scanning
class LeoTrackerApp extends StatefulWidget {
  const LeoTrackerApp({super.key});
  @override
  State<LeoTrackerApp> createState() => _LeoTrackerAppState();
}

// List of detected devices, scanning status, and user interactions such as starting/stopping scans and navigating between pages
class _LeoTrackerAppState extends State<LeoTrackerApp>
    with SingleTickerProviderStateMixin {
  final Map<String, TrackerDevice> _devicesBySig = {};

  bool scanning = false;
  int pageIndex = 0;
  DateTime? lastScanTime;
  DateTime? scanStartTime;

  int _scanSession = 0;
  int _scanSecondsElapsed = 0;
  Timer? _scanTimer;
  DateTime _mainListClearTime = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<TrackerDevice>? _bleSub;
  StreamSubscription<AccelerometerEvent>? _motionSub;
  double _lastMag = 0;
  final double _movementThreshold = 1.2;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // 10-Second Sorting Validity State
  List<String> _displayOrder = [];
  DateTime _lastSortTime = DateTime.fromMillisecondsSinceEpoch(0);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey _scanButtonKey = GlobalKey();
  final GlobalKey _trackerListKey = GlobalKey();
  final GlobalKey _firstTrackerCardKey = GlobalKey();
  final GlobalKey _identifyTabsKey = GlobalKey();
  final GlobalKey _drawerButtonKey = GlobalKey();
  final GlobalKey _drawerFiltersKey = GlobalKey();
  final GlobalKey _drawerReportsKey = GlobalKey();

  BuildContext? _materialContext;
  bool _tutorialRunning = false;

  TrackerDevice get _demoTutorialDevice {
    final now = DateTime.now().millisecondsSinceEpoch;
    return TrackerDevice(
      signature: 'tutorial-demo-airtag',
      id: 'tutorial-demo-airtag',
      kind: 'AIRTAG',
      rssi: -61,
      distanceFeet: 6.4,
      firstSeenMs: now - 6000,
      lastSeenMs: now - 1200,
      sightings: 8,
      rawFrame: '1EFF4C00121900112233445566778899AABBCC',
      smoothedRssi: -61,
      localName: '',
      isConnectable: false,
      serviceUuids: [],
    );
  }

  String get scanTimeLabel {
    final m = (_scanSecondsElapsed ~/ 60).toString();
    final s = (_scanSecondsElapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _startScanTimer() {
    _scanSecondsElapsed = 0;
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!scanning) {
        _scanTimer?.cancel();
        return;
      }
      setState(() => _scanSecondsElapsed++);
    });
  }

  void _resetScanTimer() {
    _scanTimer?.cancel();
    _scanSecondsElapsed = 0;
  }

  // Only clears devices from the main view, keeping advanced scanner intact
  Future<void> _clearMainList() async {
    setState(() {
      _mainListClearTime = DateTime.now();
    });
  }

  // Toggle the BLE scanning state when the user initiates a scan or stops it, managing the scan session and updating the UI accordingly
  @override
  void initState() {
    super.initState();

    // Show Mission Prompt on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMissionPrompt();
    });

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      _checkFirstLaunchTutorial();
    });
  }

  void _showMissionPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Select Mission Profile',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you searching a targeted package/vehicle or checking a general area for stalking?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              FiltersModel.apply(
                maxMainDistanceFt: 50.0,
                maxAdvancedDistanceFt: 200.0,
                minRssi: -100,
                filterByRssi: true,
                rssiThreshold: -90,
                sortMode: SortMode.recent,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Passive (Stalking)'),
          ),
          ElevatedButton(
            onPressed: () {
              FiltersModel.apply(
                maxMainDistanceFt: 10.0,
                maxAdvancedDistanceFt: 40.0,
                minRssi: -100,
                filterByRssi: true,
                rssiThreshold: -70,
                sortMode: SortMode.recent,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Active (Package)'),
          ),
        ],
      ),
    );
  }

  // 10-Second RSSI validity sorting
  List<TrackerDevice> get devices {
    final now = DateTime.now();
    if (now.difference(_lastSortTime).inSeconds >= 10 ||
        _displayOrder.isEmpty) {
      final list = _devicesBySig.values.toList()
        ..sort((a, b) => b.smoothedRssi.compareTo(a.smoothedRssi));
      _displayOrder = list.map((d) => d.signature).toList();
      _lastSortTime = now;
    }
    return _displayOrder
        .where(_devicesBySig.containsKey)
        .map((sig) => _devicesBySig[sig]!)
        .toList();
  }

  // Toggle the BLE scanning state when the user initiates a scan or stops it, managing the scan session and updating the UI accordingly
  Future<void> toggleScan() async {
    if (_tutorialRunning) return;
    if (scanning) {
      _scanSession++;
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
      _resetScanTimer();
      return;
    }

    // Start the BLE scan and handle the scanning state, including error handling if the scan fails to start, and updating the UI to reflect the current scanning status
    final mySession = ++_scanSession;
    try {
      final ok = await BleBridge.startScan();
      if (!ok) {
        if (!mounted || _scanSession != mySession) return;
        await _motionSub?.cancel();
        _motionSub = null;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bluetooth is not ready')));
        setState(() {
          scanning = false;
          lastScanTime = DateTime.now();
          scanStartTime = null;
        });
        _resetScanTimer();
        return;
      }
    } catch (_) {
      if (!mounted || _scanSession != mySession) return;
      await _motionSub?.cancel();
      _motionSub = null;
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
      _resetScanTimer();
      return;
    }

    if (!mounted || _scanSession != mySession) return;
    setState(() {
      scanning = true;
      scanStartTime = DateTime.now();
    });
    _startMotionDetection();
    _startScanTimer();
  }

  // Start motion detection to monitor device movement and potentially trigger BLE scans based on significant changes in accelerometer data
  void _startMotionDetection() {
    _motionSub = accelerometerEventStream().listen((event) {
      if (!scanning) return;
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      final delta = (magnitude - _lastMag).abs();
      _lastMag = magnitude;
    });
  }

  Future<void> _checkFirstLaunchTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_quick_start_guide') ?? false;
    if (seen || !mounted) return;
    if (_materialContext == null) return;
    await _showTutorialStartPrompt();
  }

  Future<void> _markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_quick_start_guide', true);
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
              },
              child: const Text('Start Guide'),
            ),
          ],
        );
      },
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

    if (scanning) {
      await BleBridge.stopScan();
      await _motionSub?.cancel();
      _motionSub = null;
      setState(() {
        scanning = false;
        lastScanTime = DateTime.now();
        scanStartTime = null;
      });
    }

    setState(() => pageIndex = 0);
    await Future.delayed(const Duration(milliseconds: 900));

    await _runDistanceTutorial();
    if (!mounted) return;

    await _openSearchTutorialFromDemoTracker();
    if (!mounted) return;

    setState(() => pageIndex = 1);
    await Future.delayed(const Duration(milliseconds: 900));

    await _runIdentifyTutorial();
    if (!mounted) return;

    await _runDrawerTutorial();
    if (!mounted) return;

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
      ),
      tutorialTarget(
        key: _trackerListKey,
        id: 'distance_list',
        title: 'Detected tags',
        body:
            'Tags will show up here along with signal strength, name, and distance.',
        yOffset: 110,
      ),
      tutorialTarget(
        key: _firstTrackerCardKey,
        id: 'open_tracker',
        title: 'Open a tracker',
        body: 'You can click a tag to open a more detailed page.',
      ),
    ]);
  }

  Future<void> _openSearchTutorialFromDemoTracker() async {
    final navContext = _materialContext;
    if (navContext == null) return;
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
        title: 'Identify page',
        body:
            'Trackers will be categorized here once the user picks a category on the other page.',
      ),
    ]);
  }

  Future<void> _runDrawerTutorial() async {
    _scaffoldKey.currentState?.openDrawer();
    await Future.delayed(const Duration(milliseconds: 600));
    await _showCoach([
      tutorialTarget(
        key: _drawerFiltersKey,
        id: 'drawer_filters',
        title: 'Filter options',
        body: 'Use these filter options to control what trackers are shown.',
      ),
      tutorialTarget(
        key: _drawerReportsKey,
        id: 'drawer_reports',
        title: 'Reports page',
        body: 'Suspect tracker reports will show up here.',
      ),
    ]);
    if (!mounted || _materialContext == null) return;
    Navigator.of(_materialContext!).pop();
    await Future.delayed(const Duration(milliseconds: 300));
  }

  // Clean up resources such as animation controllers and stream subscriptions when the widget is disposed to prevent memory leaks
  @override
  void dispose() {
    _fadeCtrl.dispose();
    _motionSub?.cancel();
    _bleSub?.cancel();
    _scanTimer?.cancel();
    super.dispose();
  }

  // Build the main UI of the app, including the navigation between different pages (DistancePage and IdentificationPage) and displaying the list of detected devices based on the current filters and sorting options
  @override
  Widget build(BuildContext context) {
    final trackedDevices = devices
        .where((d) => d.isLikelyAirTag || d.isLikelyTile || d.isLikelySamsung)
        .toList();
    final tutorialTrackedDevices = _tutorialRunning
        ? <TrackerDevice>[_demoTutorialDevice]
        : trackedDevices;

    return ValueListenableBuilder<FiltersState>(
      valueListenable: FiltersModel.notifier,
      builder: (_, filters, __) {
        final advancedDevices = devices
            .where((d) => d.distanceFeet <= filters.maxAdvancedDistanceFt)
            .where((d) => d.rssi >= filters.minRssi)
            .where(
              (d) => !filters.filterByRssi || d.rssi >= filters.rssiThreshold,
            )
            .toList();

        final nearDevices =
            advancedDevices
                .where((d) => d.distanceFeet <= filters.maxMainDistanceFt)
                .where(
                  (d) =>
                      d.lastSeenMs >= _mainListClearTime.millisecondsSinceEpoch,
                )
                .toList()
              ..sort((a, b) => a.distanceFeet.compareTo(b.distanceFeet));

        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (materialContext) {
              _materialContext = materialContext;
              final pages = [
                DistancePage(
                  nearDevices: _tutorialRunning
                      ? tutorialTrackedDevices
                      : nearDevices,
                  allTrackedDevices: advancedDevices,
                  scanning: scanning,
                  onRescan: toggleScan,
                  lastScanTime: lastScanTime,
                  scanStartTime: scanStartTime,
                  scanCountdownLabel: scanTimeLabel,
                  onRefresh: _clearMainList,
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
                    filtersTileKey: _drawerFiltersKey,
                    reportsTileKey: _drawerReportsKey,
                  ),
                  appBar: AppBar(
                    leading: IconButton(
                      key: _drawerButtonKey,
                      icon: const Icon(Icons.menu, size: 30),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    centerTitle: true,
                    title: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
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
                        BottomNavigationBarItem(
                          icon: Icon(Icons.radar),
                          label: 'Scan',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.list_alt),
                          label: 'Identify',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
