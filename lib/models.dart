// Model for representing detected tracker devices and their properties
import 'device_marks.dart';

class TrackerDevice {
  final String signature;
  final String id;
  final String kind;

  final int rssi;
  final double distanceFeet;
  final int firstSeenMs;
  final int lastSeenMs;
  final int sightings;
  final String rawFrame;

  final double smoothedRssi;
  final String localName;
  final bool isConnectable;
  final List<String> serviceUuids;

  // Constructor for initializing a TrackerDevice with all required properties
  TrackerDevice({
    required this.signature,
    required this.id,
    required this.kind,
    required this.rssi,
    required this.distanceFeet,
    required this.firstSeenMs,
    required this.lastSeenMs,
    required this.sightings,
    required this.rawFrame,
    required this.smoothedRssi,
    required this.localName,
    required this.isConnectable,
    required this.serviceUuids,
  });

  double get distance => distanceFeet;
  double get distanceMeters => distanceFeet / 3.28084;
  String get distanceFtLabel =>
      '${distanceFeet.toStringAsFixed(distanceFeet < 10 ? 1 : 0)} ft';

  bool get isLikelyAirTag => kind == 'AIRTAG';
  bool get isLikelyTile => kind == 'TILE';
  bool get isLikelySamsung =>
      kind == 'SAMSUNG' ||
      kind == 'SAMSUNG_DEVICE' ||
      kind == 'SAMSUNG_SMARTTAG';

  bool get isPossibleAirTag {
    final n = localName.toLowerCase().trim();
    if (isLikelyAirTag) return true;
    final looksUnnamed = n.isEmpty || n == 'unknown';

    final notObviousAppleHost =
        !n.contains('iphone') &&
        !n.contains('ipad') &&
        !n.contains('macbook') &&
        !n.contains('airpods') &&
        !n.contains('watch') &&
        !n.contains('imac') &&
        !n.contains('apple tv');

    final hasTrackerLikePresence = sightings >= 2;
    final signalIsRelevant = smoothedRssi >= -85;
    final hasAppleLikeSignature =
        kind == 'APPLE_DEVICE' ||
        rawFrame.toLowerCase().contains('4c00') ||
        serviceUuids.isNotEmpty;

    return (kind == 'APPLE_DEVICE' || kind == 'UNKNOWN') &&
        looksUnnamed &&
        !isConnectable &&
        hasTrackerLikePresence &&
        signalIsRelevant &&
        hasAppleLikeSignature &&
        notObviousAppleHost;
  }

  bool get isFound => distanceFeet <= 0.10;

  String get displayName {
    final customName = DeviceMarks.getName(signature);
    if (customName != null && customName.isNotEmpty) return customName;

    if (isLikelyAirTag) return 'APPLE TAG';
    if (isLikelyTile) return 'TILE TAG';
    if (isLikelySamsung) return 'SAMSUNG TAG';
    if (kind.contains('APPLE') || isPossibleAirTag) return 'FINDMY TAG';
    return 'UNKNOWN TAG';
  }

  String get displayUuid {
    if (signature.startsWith('IOS_')) {
      return signature.replaceFirst('IOS_', '');
    }
    return signature;
  }

  String get displayMac => displayUuid;
  int get rotatingMacCount => 0;

  TrackerDevice merge(TrackerDevice newer) {
    final smoothed = (smoothedRssi * 0.4) + (newer.rssi * 0.6);
    return TrackerDevice(
      signature: signature,
      id: id,
      kind: newer.kind.isNotEmpty ? newer.kind : kind,
      rssi: newer.rssi,
      distanceFeet: newer.distanceFeet,
      firstSeenMs: firstSeenMs,
      lastSeenMs: newer.lastSeenMs,
      sightings: sightings + 1,
      rawFrame: newer.rawFrame,
      smoothedRssi: smoothed,
      localName: newer.localName,
      isConnectable: newer.isConnectable,
      serviceUuids: newer.serviceUuids,
    );
  }

  factory TrackerDevice.fromNative(Map<String, dynamic> m) {
    return TrackerDevice(
      signature: (m['signature'] as String?) ?? '',
      id: (m['id'] as String?) ?? '',
      kind: (m['kind'] as String?) ?? 'UNKNOWN',
      rssi: (m['rssi'] as int?) ?? -100,
      distanceFeet: ((m['distanceFeet'] as num?) ?? 0).toDouble(),
      firstSeenMs: (m['firstSeenMs'] as int?) ?? (m['lastSeenMs'] as int?) ?? 0,
      lastSeenMs: (m['lastSeenMs'] as int?) ?? 0,
      sightings: (m['sightings'] as int?) ?? 1,
      rawFrame: (m['rawFrame'] as String?) ?? '',
      smoothedRssi: ((m['smoothedRssi'] as num?) ?? (m['rssi'] as num?) ?? -100)
          .toDouble(),
      localName: (m['localName'] as String?) ?? '',
      isConnectable: (m['isConnectable'] as bool?) ?? false,
      serviceUuids: ((m['serviceUuids'] as List?) ?? []).cast<String>(),
    );
  }
}
