import 'package:flutter/material.dart';
import 'models.dart';
import 'search_page.dart';
import 'advanced_scanner_view.dart';

class DistancePage extends StatelessWidget {
  final List<TrackerDevice> devices;
  final bool scanning;
  final VoidCallback onRescan;
  final DateTime? lastScanTime;

  const DistancePage({
    super.key,
    required this.devices,
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
    final track = devices
        .where((d) => d.isLikelyAirTag || d.isLikelyTile)
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            children: [
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
                onPressed: onRescan,
              ),
              const SizedBox(height: 10),
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

              // advanced_scanner_view.dart
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 28,
                  color: Colors.blueAccent,
                ),
                label: const Text(
                  "Advanced Scanner View",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueAccent,
                  ),
                ),
                style: OutlinedButton.styleFrom(
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
                          devices: devices,
                          scanning: scanning,
                          lastScanTime: lastScanTime,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
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
                                        (i) => Icon(
                                          Icons.signal_cellular_alt,
                                          size: 20,
                                          color:
                                              i < _bars(d.smoothedRssi.round())
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
