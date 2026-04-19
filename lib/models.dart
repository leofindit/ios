enum DeviceStatus { undesignated, friendly, nonsuspect, suspect }

extension DeviceStatusX on DeviceStatus {
  String get label {
    switch (this) {
      case DeviceStatus.undesignated:
        return "Undesignated";
      case DeviceStatus.friendly:
        return "Friendly";
      case DeviceStatus.nonsuspect:
        return "Nonsuspect";
      case DeviceStatus.suspect:
        return "Suspect";
    }
  }
}

class TrackerDevice {
  final String signature;
  final String id;
  final String logicalId;
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
  final double smoothedDistanceMeters;
  final DeviceStatus status;

  static const double _mToFt = 3.28084;

  TrackerDevice({
    required this.signature,
    required this.id,
    required this.logicalId,
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
    required this.smoothedDistanceMeters,
    required this.status,
  });

  String get stableKey {
    if (logicalId.isNotEmpty) return logicalId;
    if (id.isNotEmpty) return id;
    return signature;
  }

  double get distanceM => distanceMeters;
  double get distanceUiM => smoothedDistanceMeters;
  double get distanceFt => distanceUiM * _mToFt;

  String get distanceFtLabel =>
      '${distanceFt.toStringAsFixed(distanceFt < 10 ? 1 : 0)} ft';

  double get distance => distanceMeters;

  bool get isLikelyAirTag => kind == 'AIRTAG';
  bool get isLikelyFindMy => kind == 'FIND_MY';
  bool get isLikelyTile => kind == 'TILE';
  bool get isLikelySamsung => kind == 'SAMSUNG';

  String get displayName {
    if (isLikelyAirTag) return 'Apple AirTag';
    if (isLikelyFindMy) return 'Apple Find My'; // ← Ridge wallet shows this
    if (isLikelyTile) return 'Life360 Tile';
    if (isLikelySamsung) return 'Samsung SmartTag';

    if (kind.contains('APPLE')) return 'Apple Device';
    return 'Unknown Tracker';
  }

  String get displayMac => pinnedMac ?? lastMac ?? 'Unavailable';

  String get displayUuid {
    if (logicalId.isNotEmpty) return logicalId;
    if (id.isNotEmpty) return id;
    if (signature.isNotEmpty) return signature;
    return 'Unavailable';
  }

  String get shortMac {
    final mac = displayMac;
    if (mac == 'Unavailable') return mac;
    if (mac.length <= 4) return mac;
    return mac.substring(mac.length - 4);
  }

  String get macTail4 {
    final mac = displayMac.replaceAll(':', '').replaceAll('-', '');
    if (mac.isEmpty || mac == 'Unavailable') return '----';
    if (mac.length <= 4) return mac.toUpperCase();
    return mac.substring(mac.length - 4).toUpperCase();
  }

  bool get mayBeRotatingDuplicate =>
      rotatingMacCount > 1 && (isLikelyAirTag || isLikelyFindMy);
  String get shortUuid {
    final uuid = displayUuid;
    if (uuid == 'Unavailable') return uuid;
    if (uuid.length <= 4) return uuid;
    return uuid.substring(uuid.length - 4);
  }

  TrackerDevice withStatus(DeviceStatus s) => TrackerDevice(
    signature: signature,
    id: id,
    logicalId: logicalId,
    kind: kind,
    pinnedMac: pinnedMac,
    lastMac: lastMac,
    rssi: rssi,
    distanceMeters: distanceMeters,
    firstSeenMs: firstSeenMs,
    lastSeenMs: lastSeenMs,
    sightings: sightings,
    rotatingMacCount: rotatingMacCount,
    rawFrame: rawFrame,
    smoothedRssi: smoothedRssi,
    smoothedDistanceMeters: smoothedDistanceMeters,
    status: s,
  );

  TrackerDevice merge(TrackerDevice newer) {
    final preservedStatus = status;

    final double prevRssi = smoothedRssi;
    final double rawRssi = newer.rssi.toDouble();

    const double rssiAlpha = 0.18;
    final smoothedRssiNew =
        (prevRssi * (1 - rssiAlpha)) + (rawRssi * rssiAlpha);

    final prevD = smoothedDistanceMeters;
    final rawD = newer.distanceMeters;

    final int dtMs = (newer.lastSeenMs - lastSeenMs).clamp(1, 60000);
    final double dtS = dtMs / 1000.0;

    const double maxSpeedMps = 2.2;
    final double maxDelta = maxSpeedMps * dtS;

    double clampedRaw = rawD;
    if (prevD > 0 && rawD > 0) {
      final double delta = rawD - prevD;
      if (delta.abs() > maxDelta) {
        clampedRaw = prevD + (delta.isNegative ? -maxDelta : maxDelta);
      }
    }

    const double distAlpha = 0.08;
    final double smoothedDistNew =
        (prevD * (1 - distAlpha)) + (clampedRaw * distAlpha);

    return TrackerDevice(
      signature: newer.signature.isNotEmpty ? newer.signature : signature,
      id: newer.id.isNotEmpty ? newer.id : id,
      logicalId: newer.logicalId.isNotEmpty ? newer.logicalId : logicalId,
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
      smoothedRssi: smoothedRssiNew,
      smoothedDistanceMeters: smoothedDistNew,
      status: preservedStatus,
    );
  }

  factory TrackerDevice.fromNative(Map<String, dynamic> m) {
    final mac = m['address'] as String?;
    final int rssi = (m['rssi'] as int?) ?? -100;
    final double dist = ((m['distanceMeters'] as num?) ?? 0).toDouble();
    final int lastSeen =
        (m['lastSeenMs'] as int?) ?? DateTime.now().millisecondsSinceEpoch;

    return TrackerDevice(
      signature: (m['signature'] as String?) ?? '',
      id: (m['id'] as String?) ?? '',
      logicalId: (m['logicalId'] as String?) ?? '',
      kind: (m['kind'] as String?) ?? 'UNKNOWN',
      pinnedMac: null,
      lastMac: mac,
      rssi: rssi,
      distanceMeters: dist,
      firstSeenMs: (m['firstSeenMs'] as int?) ?? lastSeen,
      lastSeenMs: lastSeen,
      sightings: (m['sightings'] as int?) ?? 1,
      rotatingMacCount: (m['rotatingMacCount'] as int?) ?? 1,
      rawFrame: (m['rawFrame'] as String?) ?? '',
      smoothedRssi: ((m['smoothedRssi'] as num?) ?? rssi).toDouble(),
      smoothedDistanceMeters: ((m['smoothedDistanceMeters'] as num?) ?? dist)
          .toDouble(),
      status: DeviceStatus.undesignated,
    );
  }
}
