// lib/distance_page.dart

import 'package:flutter/material.dart';
import 'models.dart';
import 'search_page.dart';
import 'advanced_scanner_view.dart';

class DistancePage extends StatelessWidget {
  final List<TrackerDevice> nearDevices; // <= 15m list
  final List<TrackerDevice> allTrackedDevices; // <= 50m list
  final bool scanning;
  final Future<void> Function() onRescan; // async callback
  final DateTime? lastScanTime;

  const DistancePage({
    super.key,
    required this.nearDevices,
    required this.allTrackedDevices,
    required this.scanning,
    required this.onRescan,
    required this.lastScanTime,
  });

  String _formatTime() {
    if (lastScanTime == null) return '';
    int hour = lastScanTime!.hour % 12;
    if (hour == 0) hour = 12;
    final min = lastScanTime!.minute.toString().padLeft(2, '0');
    final am = lastScanTime!.hour >= 12 ? 'PM' : 'AM';
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
    final track = nearDevices;

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
                          devices: allTrackedDevices, // 50m list
                          scanning: scanning,
                          lastScanTime: lastScanTime,
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
                  scanning ? Icons.stop : Icons.play_arrow,
                  size: 28,
                  color: Colors.blueAccent,
                ),
                label: Text(
                  scanning ? 'Stop Scan' : 'Start Scan',
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
                  await onRescan();
                },
              ),

              const SizedBox(height: 10),

              // Scan status text
              Text(
                scanning
                    ? 'Scanning…'
                    : lastScanTime == null
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
                                    Text(
                                      d.displayName,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22,
                                      ),
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
