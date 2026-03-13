import 'package:flutter/material.dart';
import 'models.dart';

class TrackerDevicePage extends StatelessWidget {
  
  final TrackerDevice device;

  const TrackerDevicePage({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(device.displayName)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const Center(child: Icon(Icons.apple, size: 96)),
            const SizedBox(height: 24),

            _row('Type', device.displayName),
            _row('Kind', device.kind),
            _row('Device ID', device.signature),
            _row('Distance', '${device.distance.toStringAsFixed(1)} m'),
            _row('RSSI (smoothed)', device.smoothedRssi.toStringAsFixed(1)),
            _row('Rotations', device.rotatingMacCount.toString()),

            const SizedBox(height: 20),
            const Divider(),

            const Text(
              'Raw BLE Payload (hex)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            SelectableText(
              device.rawFrame.isEmpty ? 'N/A' : device.rawFrame,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// Page used for saving state of unknown / friendly / suspect
// Devices being marked on the distance page
