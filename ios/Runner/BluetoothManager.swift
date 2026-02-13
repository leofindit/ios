// ---------------------------
// leofindit_ios/ios/Runner/BluetoothManager.swift
// ---------------------------

import CoreBluetooth
import Flutter
import Foundation

final class BluetoothManager: NSObject, CBCentralManagerDelegate {

  // Contract constants
  private let TX_POWER: Double = -59.0
  private let PATH_LOSS_N: Double = 2.0  // indoor-ish
  private let TRACKER_TTL_MS: Int64 = 30_000

  private let channel: FlutterMethodChannel
  private var central: CBCentralManager!

  private var scanning = false
  // Request throttling
  private var pendingStart = false
  private var lastStartRequestMs: Int64 = 0
  private let START_REQUEST_TTL_MS: Int64 = 10_000  // only honor for 10s

  // Minimal state so we can emit stable "signature" + TTL eviction
  private struct TrackerState {
    var lastSeenMs: Int64
    var firstSeenMs: Int64
    var sightings: Int
    var rotatingMacCount: Int  // iOS can't read MAC -> stays 0
    var rawFrame: String
    var kind: String
    var lastRssi: Int
    var smoothedRssi: Int
  }

  private var states: [String: TrackerState] = [:]  // signature -> state

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    self.central = CBCentralManager(delegate: self, queue: nil)
  }

  // Flutter -> iOS
  func startScan() {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

    // If already scanning, ignore
    if scanning { return }

    // If not ready yet, remember intent and return
    guard central.state == .poweredOn else {
      pendingStart = true
      lastStartRequestMs = nowMs
      return
    }

    // Ready -> start now
    pendingStart = false
    scanning = true

    central.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    )
  }

  func stopScan() {
    pendingStart = false
    if !scanning { return }
    scanning = false
    central.stopScan()
  }

  // CBCentralManagerDelegate
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn {
      // Bluetooth turned off/reset -> stop
      stopScan()
      return
    }

    // If Bluetooth just became ready, and we recently asked to start, start now
    if pendingStart {
      let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
      if nowMs - lastStartRequestMs <= START_REQUEST_TTL_MS {
        pendingStart = false
        startScan()
      } else {
        // stale request, ignore
        pendingStart = false
      }
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {

    // iOS uses 127 as invalid RSSI (not in range)
    let rssi = RSSI.intValue
    if rssi == 127 { return }

    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

    // TTL eviction (prevents phantom buildup)
    states = states.filter { nowMs - $0.value.lastSeenMs <= TRACKER_TTL_MS }

    // Extract data first (because we log it)
    let rawFrame = extractManufacturerHex(advertisementData: advertisementData)

    let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
    let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
    let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    let serviceUuidStrings = serviceUUIDs.map { $0.uuidString.uppercased() }

    // Classify kind (best-effort)
    let kind = classifyKind(advertisementData: advertisementData)
    // Create a signature that combines all stable identifiers
    let signature = "IOS_\(kind)_\(peripheral.identifier.uuidString)"

    // Optional debug
    if localName.lowercased().contains("tag") || localName.lowercased().contains("air") {
      print(
        "BLE DEBUG name=\(localName) kind=\(kind) rssi=\(rssi) conn=\(isConnectable) services=\(serviceUuidStrings) mfg=\(rawFrame)"
      )
    }

    // update state
    let prev = states[signature]
    let firstSeen = prev?.firstSeenMs ?? nowMs
    let sightings = (prev?.sightings ?? 0) + 1

    // compute an exponential moving average for RSSI (more responsive)
    let prevSmoothed = prev?.smoothedRssi ?? rssi
    let newSmoothedDouble = (Double(prevSmoothed) * 0.4) + (Double(rssi) * 0.6)
    let newSmoothed = Int(round(newSmoothedDouble))

    states[signature] = TrackerState(
      lastSeenMs: nowMs,
      firstSeenMs: firstSeen,
      sightings: sightings,
      rotatingMacCount: 0,  // iOS cannot read device MAC
      rawFrame: rawFrame,
      kind: kind,
      lastRssi: rssi,
      smoothedRssi: newSmoothed
    )

    // distance estimate (meters)
    let distanceMeters = estimateDistanceMeters(rssi: newSmoothed)

    // Filter by kind
    let allowedKinds: Set<String> = [
      "AIRTAG", "TILE", "SAMSUNG_SMARTTAG", "SAMSUNG_DEVICE", "APPLE_DEVICE", "UNKNOWN",
    ]
    if !allowedKinds.contains(kind) {
      return
    }

    // prepare payload
    let payload: [String: Any] = [
      "id": "\(kind)_\(signature)",
      "logicalId": "\(kind)_\(signature)",
      "address": NSNull(),  // iOS: not available
      "mac": "",  // iOS: not available
      "kind": kind,
      "rssi": rssi,
      "smoothedRssi": newSmoothed,
      "distanceMeters": distanceMeters,
      "firstSeenMs": Int(firstSeen),
      "lastSeenMs": Int(nowMs),
      "sightings": sightings,
      "signature": signature,
      "rawFrame": rawFrame,
      "rotatingMacCount": 0,
      "localName": localName,
      "isConnectable": isConnectable,
      "serviceUuids": serviceUuidStrings,
    ]

    if kind == "UNKNOWN" {
      print(
        "BLE UNKNOWN name=\(localName) rssi=\(rssi) conn=\(isConnectable) services=\(serviceUuidStrings) mfg=\(rawFrame)"
      )
    }

    if kind == "SAMSUNG_DEVICE" || kind == "SAMSUNG_SMARTTAG" || kind == "TILE" || kind == "AIRTAG"
      || kind == "APPLE_DEVICE"
    {
      print(
        "BLE kind=\(kind) name=\(localName) rssi=\(rssi) conn=\(isConnectable) services=\(serviceUuidStrings) mfg=\(rawFrame)"
      )
    }

    channel.invokeMethod("onDevice", arguments: payload)
  }

  // Helpers
  private func estimateDistanceMeters(rssi: Int) -> Double {
    // 10 ^ ((txPower - rssi) / (10*n))
    let ratio = (TX_POWER - Double(rssi)) / (10.0 * PATH_LOSS_N)
    return pow(10.0, ratio)
  }

  private func classifyKind(advertisementData: [String: Any]) -> String {
    let localName =
      (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.lowercased() ?? ""

    // 1) Strong name hints (broaden tag name matching)
    if localName.contains("tile") {
      return "TILE"
    }
    // match "smarttag", "smart tag", "smart-tag", "galaxy ... tag", or samsung + tag
    if localName.contains("smarttag")
      || localName.contains("smart tag")
      || localName.contains("smart-tag")
      || (localName.contains("samsung") && localName.contains("tag"))
      || (localName.contains("galaxy") && localName.contains("tag"))
      || (localName.contains("tag") && localName.contains("smart"))
    {
      return "SAMSUNG_SMARTTAG"
    }

    // 2) Manufacturer data company id (best when present)
    if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 2
    {
      let b0 = UInt16(mfg[mfg.startIndex])
      let b1 = UInt16(mfg[mfg.startIndex + 1])
      let companyId = b0 | (b1 << 8)

      if companyId == 0x0131 { return "TILE" }

      // Samsung company ID = Samsung device, NOT necessarily SmartTag
      if companyId == 0x0075 { return "SAMSUNG_DEVICE" }

      // Apple is noisy
      if companyId == 0x004C { return "APPLE_DEVICE" }
    }

    // 3) Service UUID heuristic (sometimes present)
    if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
      let s = uuids.map { $0.uuidString.uppercased() }

      // Find My heuristic (not always visible)
      if s.contains(where: { $0.contains("FD44") }) {
        return "AIRTAG"
      }

      // Tile can also show up on these UUIDs in some models (best-effort)
      if s.contains(where: { $0.contains("FEED") || $0.contains("FEE7") }) {
        return "TILE"
      }
    }

    // If it's named "samsung" but not "smarttag", treat as generic samsung device
    if localName.contains("samsung") {
      return "SAMSUNG_DEVICE"
    }
    let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
    if localName.isEmpty && !isConnectable {
      if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
        !uuids.isEmpty
      {
        return "APPLE_DEVICE"
      }
    }
    return "UNKNOWN"
  }

  private func extractManufacturerHex(advertisementData: [String: Any]) -> String {
    guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
      return ""
    }
    return mfg.map { String(format: "%02x", $0) }.joined()
  }
}
