class TrackerDevice {
  final String signature;
  final String id;
  final String kind;

  final String? pinnedMac;
  final String? lastMac;

  final int rssi;
  final double distanceMeters;
  final int firstSeenMs;
  final int lastSeenMs;
  final int sightings;
  final int rotatingMacCount;
  final String rawFrame;

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

  double get distanceM => distanceMeters;
  double get distanceFt => distanceMeters * _mToFt;

  String get distanceFtLabel =>
      '${distanceFt.toStringAsFixed(distanceFt < 10 ? 1 : 0)} ft';

  double get distance => distanceMeters;

  bool get isLikelyAirTag => kind == 'AIRTAG';
  bool get isLikelyTile => kind == 'TILE';

  bool get isLikelySamsung =>
      kind == 'SAMSUNG' ||
      kind == 'SAMSUNG_DEVICE' ||
      kind == 'SAMSUNG_SMARTTAG';

  bool get isFound => distanceMeters <= 0.10;

  String get displayName {
    if (isLikelyAirTag) return 'Apple AirTag';
    if (isLikelyTile) return 'Tile Tracker';

    // Samsung
    if (kind == 'SAMSUNG_SMARTTAG' || kind == 'SAMSUNG') {
      return 'Samsung SmartTag';
    }
    if (kind == 'SAMSUNG_DEVICE') return 'Samsung BLE Device';

    if (kind.contains('APPLE')) return 'Apple Find My Device';
    return 'Unknown Tracker';
  }

  String get displayMac => pinnedMac ?? lastMac ?? 'Random / Rotating';

  TrackerDevice merge(TrackerDevice newer) {
    final smoothed = (smoothedRssi * 0.7) + (newer.rssi * 0.3);

    return TrackerDevice(
      signature: signature,
      id: id,
      kind: newer.kind.isNotEmpty ? newer.kind : kind,
      pinnedMac: pinnedMac ?? newer.pinnedMac, // don’t pin rotating lastMac
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
    final rotating = (m['rotatingMacCount'] as int?) ?? 0;
    final shouldPin = mac != null && rotating <= 1;

    return TrackerDevice(
      signature: (m['signature'] as String?) ?? '',
      id: (m['id'] as String?) ?? '',
      kind: (m['kind'] as String?) ?? 'UNKNOWN',
      pinnedMac: shouldPin ? mac : null,
      lastMac: mac,
      rssi: (m['rssi'] as int?) ?? -100,
      distanceMeters: ((m['distanceMeters'] as num?) ?? 0).toDouble(),
      firstSeenMs: (m['firstSeenMs'] as int?) ?? (m['lastSeenMs'] as int?) ?? 0,
      lastSeenMs: (m['lastSeenMs'] as int?) ?? 0,
      sightings: (m['sightings'] as int?) ?? 1,
      rotatingMacCount: rotating,
      rawFrame: (m['rawFrame'] as String?) ?? '',
      smoothedRssi: ((m['smoothedRssi'] as num?) ?? (m['rssi'] as num?) ?? -100)
          .toDouble(),
    );
  }
}
