// lib/distance_page.dart

import 'package:flutter/material.dart';
import 'models.dart';
import 'search_page.dart';
import 'advanced_scanner_view.dart';
import 'device_marks.dart';

class DistancePage extends StatefulWidget {
  final List<TrackerDevice> nearDevices; // <= 15m list
  final List<TrackerDevice> allTrackedDevices; // <= 50m list
  final bool scanning;
  final Future<void> Function() onRescan; // async callback
  final DateTime? lastScanTime;
  final String scanCountdownLabel;

  const DistancePage({
    super.key,
    required this.nearDevices,
    required this.allTrackedDevices,
    required this.scanning,
    required this.onRescan,
    required this.lastScanTime,
    required this.scanCountdownLabel,
  });

  @override
  State<DistancePage> createState() => _DistancePageState();
}

class _DistancePageState extends State<DistancePage> {
  @override
  void initState() {
    super.initState();
    // Listen to device marks changes to rebuild cards
    DeviceMarks.version.addListener(_onMarksChanged);
  }

  @override
  void dispose() {
    DeviceMarks.version.removeListener(_onMarksChanged);
    super.dispose();
  }

  void _onMarksChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatTime() {
    if (widget.lastScanTime == null) return '';
    int hour = widget.lastScanTime!.hour % 12;
    if (hour == 0) hour = 12;
    final min = widget.lastScanTime!.minute.toString().padLeft(2, '0');
    final am = widget.lastScanTime!.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $am';
  }

  int _bars(int rssi) {
    if (rssi >= -55) return 5;
    if (rssi >= -65) return 4;
    if (rssi >= -75) return 3;
    if (rssi >= -85) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.nearDevices;

    return Column(
      children: [
        // HEADER AREA
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            children: [
              // Show All Devices button
              OutlinedButton.icon(
                icon: const Icon(
                  Icons.search,
                  size: 22,
                  color: Colors.blueAccent,
                ),
                label: const Text(
                  'Show All Devices',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueAccent,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.grey.shade50,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: Colors.blueAccent.withOpacity(0.25),
                      width: 1.2,
                    ),
                  ),
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => FractionallySizedBox(
                      heightFactor: 0.92,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        child: AdvancedScannerView(
                          devices: widget.allTrackedDevices, // 50m list
                          scanning: widget.scanning,
                          lastScanTime: widget.lastScanTime,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),

              // Start/Stop Scan
              ElevatedButton.icon(
                icon: Icon(
                  widget.scanning ? Icons.stop : Icons.play_arrow,
                  size: 28,
                  color: Colors.blueAccent,
                ),
                label: Text(
                  widget.scanning ? 'Stop Scan' : 'Start Scan',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueAccent,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade50,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: Colors.blueAccent.withOpacity(0.25),
                      width: 1.2,
                    ),
                  ),
                ),
                onPressed: () async {
                  await widget.onRescan();
                },
              ),

              const SizedBox(height: 10),

              // Scan status text
              Text(
                widget.scanning
                    ? 'Scanning… ${widget.scanCountdownLabel}'
                    : widget.lastScanTime == null
                    ? 'No scans yet'
                    : 'Last scan ${_formatTime()}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),

        // MAIN LIST (devices <= 15m)
        Expanded(
          child: track.isEmpty
              ? const Center(
                  child: Text(
                    'No trackers detected',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: track.length,
                  itemBuilder: (_, i) {
                    final d = track[i];

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SearchPage(device: d),
                        ),
                      ),
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.signal_cellular_alt_rounded,
                                size: 46,
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            d.displayName,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.bold,
                                              fontSize: 22,
                                            ),
                                          ),
                                        ),
                                        if (DeviceMarks.get(d.signature) ==
                                            DeviceMark.friendly)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Friendly',
                                              style: TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                          )
                                        else if (DeviceMarks.get(d.signature) ==
                                            DeviceMark.unknown)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Unknown',
                                              style: TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Distance: ${d.distanceFt.toStringAsFixed(1)} ft',
                                    ),
                                    Text('RSSI: ${d.rssi} dBm'),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: List.generate(
                                        5,
                                        (idx) => Icon(
                                          Icons.signal_cellular_alt,
                                          size: 20,
                                          color:
                                              idx <
                                                  _bars(d.smoothedRssi.round())
                                              ? Colors.green
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
