// lib/search_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'device_marks.dart';
import 'models.dart';
import 'ble_bridge.dart';
import 'reports_store.dart';
import 'app_tutorial.dart';

// a detailed view of a specific detected tracker device, allowing users to see real-time distance estimates, signal strength, and other relevant information
// Also includes marking the device as Friendly, Unknown, or Suspect
class SearchPage extends StatefulWidget {
  final TrackerDevice device;
  final bool tutorialMode;
  const SearchPage({
    required this.device,
    this.tutorialMode = false,
    super.key,
  });
  @override
  State<SearchPage> createState() => _SearchPageState();
}

// Enum representing different proximity bands based on RSSI values
enum ProximityBand { immediate, nearby, close, far, unknown }

// _SearchPageState class manages real-time updates of the detected device's information, handling user interactions for marking devices, and providing visual feedback based on the device's proximity and signal strength
class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  TrackerDevice? live;
  StreamSubscription<TrackerDevice>? sub;

  Timer? _uiTimer;
  TrackerDevice? _pending;
  static const int _uiFrameMs = 60;

  static const double _foundThresholdFt = 0.33;
  static const double _foundReleaseFt = 1.15;
  static const int _foundHoldMs = 1800;

  int? _foundAtMs;
  bool _hapticFired = false;

  double? _displayDistanceFt;

  double? _dirRssi;
  double _rssiVelocity = 0.0;
  int _lastDirChangeMs = 0;

  static const double _rssiEmaAlpha = 0.18;
  static const double _velocityAlpha = 0.25;
  static const double _deadband = 0.25;
  static const int _directionHoldMs = 400;

  String direction = 'Hold steady';
  IconData arrow = Icons.navigation;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  Timer? _ageTick;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  final GlobalKey _distanceInfoKey = GlobalKey();
  final GlobalKey _signalStrengthKey = GlobalKey();
  final GlobalKey _categoryTabsKey = GlobalKey();

  bool _isManuallyFound = false;
  DateTime? _timeFound;

  @override
  void initState() {
    super.initState();
    live = widget.device;

    if (DeviceMarks.getMark(widget.device.signature) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (DeviceMarks.getMark(widget.device.signature) == null) {
          DeviceMarks.setMark(
            widget.device.signature,
            DeviceMark.nonsuspect,
          ); // Default state
        }
      });
    }

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulseCtrl);

    if (!widget.tutorialMode) {
      sub = BleBridge.detections.listen((d) {
        if (d.signature != widget.device.signature) return;
        _pending = d;
      });

      _uiTimer = Timer.periodic(const Duration(milliseconds: _uiFrameMs), (_) {
        if (!mounted || _pending == null) return;
        setState(() {
          _updateState(_pending!);
          live = _pending;
        });
      });
    } else {
      _displayDistanceFt = widget.device.distanceFeet;
      _updateState(widget.device);
    }

    _ageTick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });

    if (widget.tutorialMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        await _runTutorial();
      });
    }
  }

  Future<bool> _showCoach(List<TargetFocus> targets) async {
    if (!mounted || targets.isEmpty) return false;
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
    coach.show(context: context);
    return completer.future;
  }

  Future<void> _runTutorial() async {
    await _showCoach([
      tutorialTarget(
        key: _distanceInfoKey,
        id: 'search_distance',
        title: 'Distance and signal',
        body: 'Tracker distance and signal strengths are displayed here.',
      ),
      tutorialTarget(
        key: _signalStrengthKey,
        id: 'search_signal_colors',
        title: 'Signal strength colors',
        body:
            'Grey, yellow, and green show strength from weakest to strongest.',
      ),
      tutorialTarget(
        key: _categoryTabsKey,
        id: 'search_categories',
        title: 'Tracker categories',
        body:
            'You can put a tracker in three categories: Friendly, Nonsuspect, and Suspect. If you use Suspect, it will create a report.',
        align: ContentAlign.top,
      ),
    ]);
    if (mounted) Navigator.pop(context);
  }

  String _ageLabel(int lastSeenMs) {
    final s = ((_nowMs - lastSeenMs) / 1000).clamp(0, 999999).toDouble();
    if (s < 60) return "${s.toStringAsFixed(1)}s ago";
    final m = (s / 60).floor();
    final rs = (s - m * 60).floor();
    return "${m}m ${rs}s ago";
  }

  // Helper function to determine the proximity band based on the RSSI value of the detected device
  ProximityBand _bandFromRssi(double rssi) {
    if (rssi >= -55) return ProximityBand.immediate;
    if (rssi >= -65) return ProximityBand.nearby;
    if (rssi >= -75) return ProximityBand.close;
    if (rssi >= -85) return ProximityBand.far;
    return ProximityBand.unknown;
  }

  // Helper widget to determine the appropriate color to display based on the proximity band of the detected device
  Color _bandColor(ProximityBand band) {
    switch (band) {
      case ProximityBand.immediate:
        return const Color(0xFF2E7D32);
      case ProximityBand.nearby:
        return const Color(0xFF66BB6A);
      case ProximityBand.close:
        return const Color(0xFFF9A825);
      case ProximityBand.far:
        return const Color(0xFFEF6C00);
      case ProximityBand.unknown:
        return Colors.grey.shade500;
    }
  }

  // Helper widget to determine the appropriate label to display based on the proximity band of the detected device
  String _bandLabel(ProximityBand band) {
    switch (band) {
      case ProximityBand.immediate:
        return 'Very Close';
      case ProximityBand.nearby:
        return 'Nearby';
      case ProximityBand.close:
        return 'Close';
      case ProximityBand.far:
        return 'Far';
      case ProximityBand.unknown:
        return 'Unknown';
    }
  }

  // Helper function handles the logic for determining whether the device is considered found, updating the display distance, and providing feedback about whether the user is getting closer or moving away from the device
  void _updateState(TrackerDevice d) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawDist = d.distanceFeet;

    _displayDistanceFt ??= rawDist;
    _displayDistanceFt = (_displayDistanceFt! * 0.90) + (rawDist * 0.10);

    final rawRssi = d.rssi.toDouble();
    _dirRssi ??= rawRssi;

    final prevRssi = _dirRssi!;
    _dirRssi = (_dirRssi! * (1 - _rssiEmaAlpha)) + (rawRssi * _rssiEmaAlpha);

    final delta = _dirRssi! - prevRssi;
    _rssiVelocity =
        (_rssiVelocity * (1 - _velocityAlpha)) + (delta * _velocityAlpha);

    if (_rssiVelocity.abs() < _deadband) {
      direction = 'Hold steady';
      arrow = Icons.navigation;
      return;
    }

    if (now - _lastDirChangeMs < _directionHoldMs) return;

    if (_rssiVelocity > 0) {
      direction = 'Getting closer';
      arrow = Icons.arrow_circle_up_rounded;
      _lastDirChangeMs = now;
    } else {
      direction = 'Moving away';
      arrow = Icons.arrow_circle_down_rounded;
      _lastDirChangeMs = now;
    }
  }

  void _markFound(TrackerDevice d) async {
    await BleBridge.stopScan();
    setState(() {
      _isManuallyFound = true;
      _timeFound = DateTime.now();
    });
  }

  void _submitReport(TrackerDevice d) {
    final ctrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Submit Case Report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UUID: ${d.displayUuid}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Found: ${_timeFound?.toString().split('.')[0] ?? ""}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Describe circumstances (No PII)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setState(() => isSubmitting = true);
                      final payload =
                          "UUID: ${d.displayUuid}\nFound: ${_timeFound?.toString().split('.')[0]}\n\n${ctrl.text}";
                      await ReportsStore.sendAnonymousFeedback(payload);
                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report securely submitted.'),
                          ),
                        );
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Report'),
            ),
          ],
        ),
      ),
    );
  }

  // Helper function to display a dialog for submitting anonymous feedback
  @override
  void dispose() {
    sub?.cancel();
    _uiTimer?.cancel();
    _ageTick?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // Build the UI for the SearchPage,
  // Also includes buttons for marking the device as Friendly, Unknown, or Suspect
  @override
  Widget build(BuildContext context) {
    final d = live ?? widget.device;
    final band = _bandFromRssi(d.smoothedRssi);
    final color = _bandColor(band);
    final mark = DeviceMarks.getMark(d.signature) ?? DeviceMark.nonsuspect;

    return Scaffold(
      appBar: AppBar(
        title: Text(d.displayName, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isManuallyFound) ...[
                Container(
                  width: 170,
                  height: 170,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF0996D1), Color(0xFF2084E8)],
                    ),
                  ),
                  child: Icon(arrow, size: 90, color: Colors.white),
                ),
                const SizedBox(height: 22),
                Text(
                  direction,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  key: _distanceInfoKey,
                  children: [
                    Text(
                      '${(_displayDistanceFt ?? d.distanceFeet).toStringAsFixed(2)} ft',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "RSSI: ${d.rssi} dBm • Seen ${_ageLabel(d.lastSeenMs)}",
                      style: const TextStyle(fontFamily: 'Inter'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  key: _signalStrengthKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: Text(
                    _bandLabel(band),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Mark as Found'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _markFound(d),
                ),
              ] else ...[
                const Text(
                  'DEVICE FOUND',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'UUID: ${d.displayUuid}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Date/Time: ${_timeFound.toString().split('.')[0]}'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.report),
                  label: const Text('Create Report'),
                  onPressed: () => _submitReport(d),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                key: _categoryTabsKey,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _MarkTabs(
                  selected: mark,
                  onSelect: (m) {
                    setState(() => DeviceMarks.setMark(d.signature, m));
                    if (m == DeviceMark.suspect && !widget.tutorialMode)
                      ReportsStore.createFromDevice(d);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'UUID: ${d.displayUuid}',
                style: const TextStyle(fontFamily: 'Inter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom widget for displaying a button to mark a device as Friendly, Unknown, or Suspect
class _MarkTabs extends StatelessWidget {
  final DeviceMark selected;
  final ValueChanged<DeviceMark> onSelect;

  const _MarkTabs({required this.selected, required this.onSelect});

  static const Color _friendly = Color(0xFF2E7D32);
  static const Color _suspect = Color(0xFFD9534F);
  static const Color _nonsuspect = Color(0xFF1500FF);

  // Build the UI for the _MarkButton, displaying an icon and label with styling that changes based on whether the button is selected or not
  @override
  Widget build(BuildContext context) {
    final bg = Colors.grey.shade100;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              label: 'Suspect',
              color: _suspect,
              selected: selected == DeviceMark.suspect,
              onTap: () => onSelect(DeviceMark.suspect),
            ),
          ),
          Expanded(
            child: _Pill(
              label: 'Friendly',
              color: _friendly,
              selected: selected == DeviceMark.friendly,
              onTap: () => onSelect(DeviceMark.friendly),
            ),
          ),
          Expanded(
            child: _Pill(
              label: 'Nonsuspect',
              color: _nonsuspect,
              selected: selected == DeviceMark.nonsuspect,
              onTap: () => onSelect(DeviceMark.nonsuspect),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? Colors.grey.shade300 : Colors.transparent,
          width: 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                  color: Colors.black.withOpacity(0.06),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.signal_cellular_alt_rounded, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                fontSize: 14,
                color: selected ? Colors.black : Colors.grey.shade700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
