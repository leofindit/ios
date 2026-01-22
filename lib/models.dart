class TrackerDevice {
  final String signature;
  final String id;
  final String kind;

  // First stable MAC ever observed (never overwritten)
  final String? pinnedMac;

  // Last observed MAC (may rotate)
  final String? lastMac;

  final int rssi;
  final double distanceMeters;
  final int firstSeenMs;
  final int lastSeenMs;
  final int sightings;
  final int rotatingMacCount;
  final String rawFrame;

  /// Smoothed RSSI (EMA)
  final double smoothedRssi;

  static const double _mToFt = 3.28084;

  TrackerDevice({
    required this.signature,
    required this.id,
    required this.kind,
    required this.pinnedMac,
    required this.lastMac,
    required this.rssi,
    required this.distanceMeters,
    required this.firstSeenMs,
    required this.lastSeenMs,
    required this.sightings,
    required this.rotatingMacCount,
    required this.rawFrame,
    required this.smoothedRssi,
  });

  // Keep meters as the internal unit for logic.
  double get distanceM => distanceMeters;

  // Convenience: feet for UI.
  double get distanceFt => distanceMeters * _mToFt;

  String get distanceFtLabel =>
      '${distanceFt.toStringAsFixed(distanceFt < 10 ? 1 : 0)} ft';

  // Backwards-compatible alias if you were using `distance` before.
  double get distance => distanceMeters;

  bool get isLikelyAirTag => kind == 'AIRTAG';
  bool get isLikelyTile => kind == 'TILE';
  bool get isLikelySamsung => kind == 'SAMSUNG';

  bool get isFound => distanceMeters <= 0.10;

  String get displayName {
    if (isLikelyAirTag) return 'Apple AirTag';
    if (isLikelyTile) return 'Tile Tracker';
    if (isLikelySamsung) return 'Samsung SmartTag';
    if (kind.contains('APPLE')) return 'Apple Find My Device';
    return 'Unknown Tracker';
  }

  String get displayMac => pinnedMac ?? lastMac ?? 'Random / Rotating';

  TrackerDevice merge(TrackerDevice newer) {
    // Quick-ish EMA.
    final smoothed = (smoothedRssi * 0.7) + (newer.rssi * 0.3);

    return TrackerDevice(
      signature: signature,
      id: id,
      kind: newer.kind.isNotEmpty ? newer.kind : kind,
      pinnedMac: pinnedMac ?? newer.lastMac,
      lastMac: newer.lastMac,
      rssi: newer.rssi,
      distanceMeters: newer.distanceMeters,
      firstSeenMs: firstSeenMs,
      lastSeenMs: newer.lastSeenMs,
      sightings: sightings + 1,
      rotatingMacCount: newer.rotatingMacCount,
      rawFrame: newer.rawFrame,
      smoothedRssi: smoothed,
    );
  }

  factory TrackerDevice.fromNative(Map<String, dynamic> m) {
    final mac = m['address'] as String?;

    return TrackerDevice(
      signature: (m['signature'] as String?) ?? '',
      id: (m['id'] as String?) ?? '',
      kind: (m['kind'] as String?) ?? 'UNKNOWN',
      pinnedMac: mac,
      lastMac: mac,
      rssi: (m['rssi'] as int?) ?? -100,
      distanceMeters: ((m['distanceMeters'] as num?) ?? 0).toDouble(),
      firstSeenMs: (m['lastSeenMs'] as int?) ?? 0,
      lastSeenMs: (m['lastSeenMs'] as int?) ?? 0,
      sightings: 1,
      rotatingMacCount: (m['rotatingMacCount'] as int?) ?? 1,
      rawFrame: (m['rawFrame'] as String?) ?? '',
      smoothedRssi: ((m['rssi'] as num?) ?? -100).toDouble(),
    );
  }
}
