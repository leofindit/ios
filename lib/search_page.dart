// lib/search_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'device_marks.dart';
import 'models.dart';
import 'ble_bridge.dart';

// The SearchPage widget provides a detailed view of a specific detected tracker device, allowing users to see real-time distance estimates, signal strength, and other relevant information
// Also includes functionality for marking the device as Friendly, Unknown, or Suspect, helping users manage their detected devices effectively
class SearchPage extends StatefulWidget {
  final TrackerDevice device;

  const SearchPage({required this.device, super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

// Enum representing different proximity bands based on RSSI values, used to categorize the distance of detected devices and provide visual feedback to users about their proximity
enum ProximityBand { immediate, nearby, close, far, unknown }

// The _SearchPageState class manages the state of the SearchPage, including real-time updates of the detected device's information, handling user interactions for marking devices, and providing visual feedback based on the device's proximity and signal strength
class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  TrackerDevice? live;
  StreamSubscription<TrackerDevice>? sub;

  Timer? _uiTimer;
  TrackerDevice? _pending;
  static const int _uiFrameMs = 60;

  static const int _foundHoldMs = 1800;
  static const double _foundReleaseRssi = -62;

  int? _foundAtMs;
  bool _hapticFired = false;

  double? _displayDistanceM;

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

  // Initialize the state of the SearchPage, setting up the necessary subscriptions to receive real-time updates about the detected device, and configuring timers and animations to provide visual feedback based on the device's proximity and signal strength
  @override
  void initState() {
    super.initState();
    live = widget.device;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_pulseCtrl);

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
  }

  bool _isFound(TrackerDevice d) {
    return d.smoothedRssi >= -55;
  }

  String _feetLabel(double meters) {
    final feet = meters * 3.28084;
    return '${feet.toStringAsFixed(feet < 10 ? 1 : 0)} ft';
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

    final rawDist = d.distanceM;
    _displayDistanceM ??= rawDist;
    _displayDistanceM = (_displayDistanceM! * 0.25) + (rawDist * 0.75);

    if (_isFound(d)) {
      _foundAtMs ??= now;

      if (!_hapticFired) {
        HapticFeedback.lightImpact();
        _hapticFired = true;
      }

      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }

      direction = 'FOUND';
      arrow = Icons.check_rounded;
      return;
    }

    if (_foundAtMs != null) {
      final held = now - _foundAtMs! < _foundHoldMs;
      final stillClose = d.smoothedRssi >= _foundReleaseRssi;

      if (held || stillClose) {
        direction = 'FOUND';
        arrow = Icons.check_rounded;
        return;
      }

      _foundAtMs = null;
      _hapticFired = false;
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }

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

  // Clean up resources when the SearchPage is disposed, including canceling any active subscriptions to device updates, stopping timers, and disposing of animation controllers
  @override
  void dispose() {
    sub?.cancel();
    _uiTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // Build the UI for the SearchPage, displaying real-time information about the detected device, including its estimated distance, signal strength, and proximity band
  // Also includes buttons for marking the device as Friendly, Unknown, or Suspect, allowing users to manage their detected devices effectively
  @override
  Widget build(BuildContext context) {
    final d = live ?? widget.device;

    final band = _bandFromRssi(d.smoothedRssi);
    final color = _bandColor(band);

    final mark = DeviceMarks.get(d.signature);

    return Scaffold(
      appBar: AppBar(title: Text(d.displayName)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _foundAtMs != null
                  ? _pulseAnim
                  : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _foundAtMs != null ? color : null,
                  gradient: _foundAtMs != null
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF0996D1), Color(0xFF2084E8)],
                        ),
                ),
                child: Icon(arrow, size: 90, color: Colors.white),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              direction,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_displayDistanceM ?? d.distanceM).toStringAsFixed(2)} m • ${_feetLabel(_displayDistanceM ?? d.distanceM)}',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Text(
                _bandLabel(band),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _MarkButton(
                      label: 'Friendly',
                      icon: Icons.check_circle_rounded,
                      selected: mark == DeviceMark.friendly,
                      selectedColor: Colors.green,
                      onTap: () {
                        setState(() {
                          final current = DeviceMarks.get(d.signature);
                          if (current == DeviceMark.friendly) {
                            DeviceMarks.clear(d.signature);
                          } else {
                            DeviceMarks.set(d.signature, DeviceMark.friendly);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _MarkButton(
                      label: 'Unknown',
                      icon: Icons.help_outline_rounded,
                      selected: mark == DeviceMark.unknown,
                      selectedColor: Colors.blueGrey,
                      onTap: () {
                        setState(() {
                          final current = DeviceMarks.get(d.signature);
                          if (current == DeviceMark.unknown) {
                            DeviceMarks.clear(d.signature);
                          } else {
                            DeviceMarks.set(d.signature, DeviceMark.unknown);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _MarkButton(
                      label: 'Suspect',
                      icon: Icons.warning_amber_rounded,
                      selected: mark == DeviceMark.suspect,
                      selectedColor: Colors.orange,
                      onTap: () {
                        setState(() {
                          final current = DeviceMarks.get(d.signature);
                          if (current == DeviceMark.suspect) {
                            DeviceMarks.clear(d.signature);
                          } else {
                            DeviceMarks.set(d.signature, DeviceMark.suspect);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('UUID: ${d.displayUuid}'),
          ],
        ),
      ),
    );
  }
}

// Custom widget for displaying a button to mark a device as Friendly, Unknown, or Suspect
// The button changes its appearance based on whether it is selected or not, providing visual feedback to users about the current mark/status of the device
class _MarkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  // Constructor for the _MarkButton widget, requiring a label, icon, selected state, selected color, and onTap callback
  const _MarkButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  // Build the UI for the _MarkButton, displaying an icon and label with styling that changes based on whether the button is selected or not
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 46,
      decoration: BoxDecoration(
        color: selected
            ? selectedColor.withOpacity(0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? selectedColor : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? selectedColor : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? selectedColor : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
