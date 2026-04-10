import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_marks.dart';
import 'models.dart';
import 'ble_bridge.dart';
import 'reports_store.dart';
import 'app_tutorial.dart';

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

enum ProximityBand { immediate, nearby, close, far, unknown }

class _SearchPageState extends State<SearchPage> {
  TrackerDevice? live;
  StreamSubscription<TrackerDevice>? sub;

  Timer? _uiTimer;
  TrackerDevice? _pending;
  static const int _uiFrameMs = 60;

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
        showSkip: false,
      ),
      tutorialTarget(
        key: _signalStrengthKey,
        id: 'search_signal_colors',
        title: 'Signal strength colors',
        body:
            'Grey, yellow, and green show strength from weakest to strongest.',
        showSkip: false,
      ),
      tutorialTarget(
        key: _categoryTabsKey,
        id: 'search_categories',
        title: 'Tracker categories',
        body:
            'You can put a tracker in three categories: Friendly, Undesignated, and Suspect. If you use Suspect, it will create a report.',
        align: ContentAlign.top,
        showSkip: false,
      ),
    ]);
    if (mounted) Navigator.pop(context);
  }

  String _ageLabel(int lastSeenMs) {
    final s = ((_nowMs - lastSeenMs) / 1000).clamp(0, 999999).toInt();
    if (s < 60) return "${s}s ago";
    final m = (s ~/ 60);
    final rs = (s % 60);
    return "${m}m ${rs}s ago";
  }

  ProximityBand _bandFromRssi(double rssi) {
    if (rssi >= -55) return ProximityBand.immediate;
    if (rssi >= -65) return ProximityBand.nearby;
    if (rssi >= -75) return ProximityBand.close;
    if (rssi >= -85) return ProximityBand.far;
    return ProximityBand.unknown;
  }

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
      arrow = Icons.arrow_upward;
      _lastDirChangeMs = now;
    } else {
      direction = 'Moving away';
      arrow = Icons.arrow_downward;
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspect Tag Report'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'I opt in to SMS with LeoFindIt developers only regarding the matter in my feedback. I can send STOP anytime to opt out.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Classified Suspect: ${DateTime.now().toString().split('.')[0]}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'UUID: ...${d.shortUuid}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'First Scanned: ${DateTime.fromMillisecondsSinceEpoch(d.firstSeenMs).toString().split('.')[0]}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'Last Scanned: ${DateTime.fromMillisecondsSinceEpoch(d.lastSeenMs).toString().split('.')[0]}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'Marked Found: ${_timeFound?.toString().split('.')[0] ?? "N/A"}',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'Last Distance: ${d.distanceFeet.toStringAsFixed(1)} ft',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                'Suggest: Screen shot this report, photograph the tag where found, and zoom in to photograph the tag serial number.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please include a sentence stating the crime and resolution and any app feedback below:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Crime, resolution, feedback...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final body =
                  "LeoFindIt Suspect Report:\nUUID: ...${d.shortUuid}\nFirst Scanned: ${DateTime.fromMillisecondsSinceEpoch(d.firstSeenMs)}\nLast Scanned: ${DateTime.fromMillisecondsSinceEpoch(d.lastSeenMs)}\nFound: ${_timeFound}\nLast Distance: ${d.distanceFeet.toStringAsFixed(1)} ft\n\nNotes: ${ctrl.text}";
              final uri = Uri.parse(
                "mailto:feedback@leofindit.com?subject=${Uri.encodeComponent('LeoFindIt Suspect Report')}&body=${Uri.encodeComponent(body)}",
              );
              try {
                await launchUrl(uri);
              } catch (e) {
                // Ignore failure if emulator doesn't support Mail
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Email'),
          ),
          ElevatedButton(
            onPressed: () async {
              final body =
                  "LeoFindIt Suspect Report:\nUUID: ...${d.shortUuid}\nFirst Scanned: ${DateTime.fromMillisecondsSinceEpoch(d.firstSeenMs)}\nLast Scanned: ${DateTime.fromMillisecondsSinceEpoch(d.lastSeenMs)}\nFound: ${_timeFound}\nLast Distance: ${d.distanceFeet.toStringAsFixed(1)} ft\n\nNotes: ${ctrl.text}";
              final uri = Uri.parse(
                "sms:9383686348?body=${Uri.encodeComponent(body)}",
              );
              try {
                await launchUrl(uri);
              } catch (e) {
                // Ignore failure if emulator doesn't support SMS
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('SMS'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    sub?.cancel();
    _uiTimer?.cancel();
    _ageTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = live ?? widget.device;
    final band = _bandFromRssi(d.smoothedRssi);
    final color = _bandColor(band);
    final DeviceMark? mark = DeviceMarks.getMark(d.signature);

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
                TutorialBlinker(
                  isTutorialMode: widget.tutorialMode,
                  child: Column(
                    key: _distanceInfoKey,
                    children: [
                      Text(
                        "RSSI: ${d.rssi} dBm",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Distance: ${(_displayDistanceFt ?? d.distanceFeet).toStringAsFixed(2)} ft',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Seen ${_ageLabel(d.lastSeenMs)}",
                        style: const TextStyle(fontFamily: 'Inter'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TutorialBlinker(
                  isTutorialMode: widget.tutorialMode,
                  child: Container(
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
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
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
                  'UUID: ...${d.shortUuid}',
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
              TutorialBlinker(
                isTutorialMode: widget.tutorialMode,
                child: Padding(
                  key: _categoryTabsKey,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _MarkTabs(
                    selected: mark,
                    onSelect: (m) {
                      // Toggles classification OFF if already selected
                      final DeviceMark? newMark = (m == mark) ? null : m;

                      setState(() => DeviceMarks.setMark(d.signature, newMark));

                      if (newMark == DeviceMark.suspect &&
                          !widget.tutorialMode) {
                        ReportsStore.createFromDevice(d);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'UUID: ...${d.shortUuid}',
                style: const TextStyle(fontFamily: 'Inter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkTabs extends StatelessWidget {
  final DeviceMark? selected;
  final ValueChanged<DeviceMark> onSelect;
  const _MarkTabs({required this.selected, required this.onSelect});

  static const Color _friendly = Color(0xFF2E7D32);
  static const Color _suspect = Color(0xFFD9534F);
  static const Color _undesignated = Color(0xFF1500FF);

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
              label: 'Undesig.',
              color: _undesignated,
              selected: selected == DeviceMark.undesignated,
              onTap: () => onSelect(DeviceMark.undesignated),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.signal_cellular_alt_rounded, size: 14, color: color),
              const SizedBox(width: 2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      fontSize: 12,
                      color: selected ? Colors.black : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
