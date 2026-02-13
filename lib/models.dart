import 'dart:math';

class TrackerDevice {
  final String localName;
  final bool isConnectable;
  final List<String> serviceUuids;

  final String signature;
  final String id;
  final String kind;

  final String? pinnedId;
  final String? lastId;

  // Deprecated: replaced by pinnedId/lastId which use system-provided UUIDs/signature
  // kept for compatibility internally but not populated on iOS

  final int rssi;
  final double distanceMeters;
  final int firstSeenMs;
  final int lastSeenMs;
  final int sightings;
  final int rotatingMacCount;
  final String rawFrame;

  final double smoothedRssi;

  static const double _mToFt = 3.28084;
  // Distance estimation constants (match native)
  static const double _txPower = -59.0;
  static const double _pathLossN = 2.0;

  TrackerDevice({
    required this.signature,
    required this.id,
    required this.kind,
    required this.pinnedId,
    required this.lastId,
    required this.rssi,
    required this.distanceMeters,
    required this.firstSeenMs,
    required this.lastSeenMs,
    required this.sightings,
    required this.rotatingMacCount,
    required this.rawFrame,
    required this.smoothedRssi,
    required this.localName,
    required this.isConnectable,
    required this.serviceUuids,
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

  bool get looksLikeNonTracker {
    final n = localName.toLowerCase();
    // Common non-tracker device names
    if (n.contains('macbook') ||
        n.contains('iphone') ||
        n.contains('ipad') ||
        n.contains('watch') ||
        n.contains('airpods') ||
        n.contains('imac') ||
        n.contains('apple tv')) {
      return true;
    }
    // Many normal devices are connectable; trackers often aren't.
    // If it's connectable and we didn't classify it as a tracker, treat it as noise.
    if (isConnectable && !isLikelyTile && !isLikelySamsung && !isLikelyAirTag) {
      return true;
    }
    return false;
  }

  String get displayName {
    if (isLikelyAirTag) return 'Apple AirTag';
    if (isLikelyTile) return 'Tile Tracker';

    if (kind == 'SAMSUNG_SMARTTAG' || kind == 'SAMSUNG') {
      return 'Samsung SmartTag';
    }
    if (kind == 'SAMSUNG_DEVICE') return 'Samsung BLE Device';

    if (kind.contains('APPLE')) return 'Apple Find My Device';
    return 'Unknown Tracker';
  }

  // New API: display the stable device identifier (UUID/signature)
  String get displayId => pinnedId ?? lastId ?? 'Random / Rotating';

  // Backwards-compatible alias
  String get displayMac => displayId;

  TrackerDevice merge(TrackerDevice newer) {
    // smoothing for RSSI to reduce UI jitter
    final smoothed = (smoothedRssi * 0.4) + (newer.rssi * 0.6);
    final distanceFromSmoothed = pow(
      10.0,
      (_txPower - smoothed) / (10.0 * _pathLossN),
    ).toDouble();

    return TrackerDevice(
      signature: signature,
      id: id,
      kind: newer.kind.isNotEmpty ? newer.kind : kind,
      pinnedId: pinnedId ?? newer.pinnedId,
      lastId: newer.lastId,
      rssi: newer.rssi,
      distanceMeters: newer.distanceMeters,
      firstSeenMs: firstSeenMs,
      lastSeenMs: newer.lastSeenMs,
      sightings: sightings + 1,
      rotatingMacCount: newer.rotatingMacCount,
      rawFrame: newer.rawFrame,
      smoothedRssi: smoothed,

      localName: newer.localName,
      isConnectable: newer.isConnectable,
      serviceUuids: newer.serviceUuids,
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
      pinnedId: (m['pinnedId'] as String?) ?? (shouldPin ? mac : null),
      lastId: (m['lastId'] as String?) ?? mac,
      rssi: (m['rssi'] as int?) ?? -100,
      distanceMeters: ((m['distanceMeters'] as num?) ?? 0).toDouble(),
      firstSeenMs: (m['firstSeenMs'] as int?) ?? (m['lastSeenMs'] as int?) ?? 0,
      lastSeenMs: (m['lastSeenMs'] as int?) ?? 0,
      sightings: (m['sightings'] as int?) ?? 1,
      rotatingMacCount: rotating,
      rawFrame: (m['rawFrame'] as String?) ?? '',
      smoothedRssi: ((m['smoothedRssi'] as num?) ?? (m['rssi'] as num?) ?? -100)
          .toDouble(),

      localName: (m['localName'] as String?) ?? '',
      isConnectable: (m['isConnectable'] as bool?) ?? false,
      serviceUuids: ((m['serviceUuids'] as List?) ?? []).cast<String>(),
    );
  }
}
