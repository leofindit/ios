package com.example.leo_find_it

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.security.MessageDigest
import kotlin.math.pow

// Non-Apple tracker scanner (Tile + Samsung)
// Correct behavior:
// Stable logical identity
// No phantom trackers
// TTL eviction
// Proper MAC rotation tracking

class NonAppleTrackerScanner(
    context: Context,
    private val onTrackerUpdate: (AirTagScanner.DetectedTracker) -> Unit
) {

    companion object {
        private const val TAG = "NonAppleScanner"

        private const val TILE_MFG_ID = 0x0131
        private const val SAMSUNG_MFG_ID = 0x0075

        private val TILE_UUIDS = setOf(
            ParcelUuid.fromString("0000FEED-0000-1000-8000-00805F9B34FB"),
            ParcelUuid.fromString("0000FEE7-0000-1000-8000-00805F9B34FB")
        )

        private const val STABLE_PREFIX_LEN = 6
        private const val TRACKER_TTL_MS = 30_000L
    }

    private enum class Kind { TILE, SAMSUNG }

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        mgr.adapter
    }

    private val scanner get() = bluetoothAdapter?.bluetoothLeScanner
    private var scanning = false

    private data class TrackerState(
        var lastId: String?,
        var rotatingMacCount: Int,
        var lastSeenMs: Long
    )

    private val states = mutableMapOf<String, TrackerState>()

    fun start() {
        if (scanning || bluetoothAdapter?.isEnabled != true) return
        try {
            scanning = true
            scanner?.startScan(null, buildSettings(), callback)
            Log.i(TAG, "Non-Apple scan started")
        } catch (e: SecurityException) {
            scanning = false
            Log.w(TAG, "Non-Apple scan blocked", e)
        }
    }

    fun stop() {
        if (!scanning) return
        try {
            scanner?.stopScan(callback)
        } catch (_: SecurityException) {
        }
        scanning = false
    }

    private val callback = object : ScanCallback() {
        override fun onScanResult(type: Int, result: ScanResult) = handle(result)
        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { handle(it) }
        }
    }

    private fun handle(result: ScanResult) {
        val record = result.scanRecord ?: return
        val bytes = record.bytes ?: return
        val now = System.currentTimeMillis()

        val tileMfg = record.manufacturerSpecificData.get(TILE_MFG_ID)
        val samsungMfg = record.manufacturerSpecificData.get(SAMSUNG_MFG_ID)

        val kind = when {
            tileMfg != null || record.serviceUuids?.any { it in TILE_UUIDS } == true ->
                Kind.TILE

            samsungMfg != null ->
                Kind.SAMSUNG

            else -> return
        }

        // Evict stale trackers
        states.entries.removeIf {
            now - it.value.lastSeenMs > TRACKER_TTL_MS
        }

        // Stable identity source (never rotating bytes)
        val identitySource = when (kind) {
            Kind.TILE -> when {
                tileMfg != null -> tileMfg
                record.serviceData.isNotEmpty() -> record.serviceData.values.first()
                else -> return
            }

            Kind.SAMSUNG -> samsungMfg ?: return
        }

        val stablePart =
            identitySource.copyOfRange(0, minOf(STABLE_PREFIX_LEN, identitySource.size))

        val signature = sha1(stablePart)
        val idOrMac = result.device?.address
        val rssi = result.rssi

        val state = states.getOrPut(signature) {
            TrackerState(
                lastId = idOrMac,
                rotatingMacCount = if (idOrMac.isNullOrBlank()) 0 else 1,
                lastSeenMs = now
            )
        }

        if (!idOrMac.isNullOrBlank() && idOrMac != state.lastId) {
            state.lastId = idOrMac
            state.rotatingMacCount += 1
        }

        state.lastSeenMs = now

        val outKind = when (kind) {
            Kind.TILE -> AirTagScanner.TrackerKind.TILE
            Kind.SAMSUNG -> AirTagScanner.TrackerKind.SAMSUNG
        }

        onTrackerUpdate(
            AirTagScanner.DetectedTracker(
                id = "${outKind.name}_$signature",
                logicalId = "${outKind.name}_$signature",
                kind = outKind,
                address = mac,
                rssi = rssi,
                distanceMeters = estimateDistance(rssi),
                lastSeenMs = now,
                signature = signature,
                rawFrame = bytes.toHex(),
                rotatingMacCount = state.rotatingMacCount
            )
        )
    }

    private fun buildSettings(): ScanSettings =
        ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

    private fun estimateDistance(rssi: Int, txPower: Int = -59): Double {
        val ratio = (txPower - rssi) / (10.0 * 2.0)
        return 10.0.pow(ratio)
    }

    private fun sha1(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-1")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it) }
}
