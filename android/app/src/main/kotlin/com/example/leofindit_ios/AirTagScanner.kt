package com.example.leo_find_it

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import java.security.MessageDigest
import kotlin.math.pow


// AirTag specific / Apple Find My BLE scanner
// Correct behavior:
// Groups rotating payloads under a single logical tracker
// Prevents phantom / duplicate trackers
// Evicts stale old trackers / signals

class AirTagScanner(
    private val context: Context,
    private val onTrackerUpdate: (DetectedTracker) -> Unit
) {

    companion object {
        private const val TAG = "AirTagScanner"

        private const val APPLE_MFG_ID = 0x004C

        private val FIND_MY_UUID =
            ParcelUuid.fromString("0000FD44-0000-1000-8000-00805F9B34FB")

        private const val STABLE_PREFIX_LEN = 4
        private const val TRACKER_TTL_MS = 20_000L
    }

    enum class TrackerKind {
        AIRTAG,
        TILE,
        SAMSUNG,
        APPLE_DEVICE,
        UNKNOWN
    }

    data class DetectedTracker(
        val id: String,
        val logicalId: String,
        val kind: TrackerKind,
        val address: String?,
        val rssi: Int,
        val distanceMeters: Double,
        val lastSeenMs: Long,
        val signature: String,
        val rawFrame: String,
        val rotatingMacCount: Int
    )

    private data class TrackerState(
        val signature: String,
        var lastRssi: Int,
        var lastSeenMs: Long,
        var rawFrame: String,
        var lastId: String?,
        var rotatingMacCount: Int
    )

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        mgr.adapter
    }

    private val scanner get() = bluetoothAdapter?.bluetoothLeScanner
    private val trackers = mutableMapOf<String, TrackerState>()

    private var scanning = false

    fun start() {
        if (scanning || bluetoothAdapter?.isEnabled != true) return
        try {
            scanning = true
            scanner?.startScan(null, buildSettings(), callback)
            Log.i(TAG, "AirTag scan started")
        } catch (e: SecurityException) {
            scanning = false
            Log.w(TAG, "BLE scan blocked", e)
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

        val fd44 = record.serviceData[FIND_MY_UUID]
        val appleMfg = record.manufacturerSpecificData.get(APPLE_MFG_ID)

        val isAirTag =
            fd44 != null ||
                    (appleMfg != null && isAirTagManufacturerFrame(appleMfg))

        if (!isAirTag) return

        // Remove stale trackers
        trackers.entries.removeIf {
            now - it.value.lastSeenMs > TRACKER_TTL_MS
        }

        // Stable fingerprint (never rotating bytes)
        val stableSource = when {
            fd44 != null && fd44.size >= STABLE_PREFIX_LEN ->
                fd44.copyOfRange(0, STABLE_PREFIX_LEN)

            appleMfg != null && appleMfg.size >= STABLE_PREFIX_LEN ->
                appleMfg.copyOfRange(0, STABLE_PREFIX_LEN)

            else -> return
        }

        val signature = sha1(stableSource)
        val idOrMac = result.device?.address
        val rssi = result.rssi
        val rawHex = bytes.toHex()

        val state = trackers.getOrPut(signature) {
            TrackerState(
                signature = signature,
                lastRssi = rssi,
                lastSeenMs = now,
                rawFrame = rawHex,
                lastId = idOrMac,
                rotatingMacCount = if (idOrMac.isNullOrBlank()) 0 else 1
            )
        }

            if (!idOrMac.isNullOrBlank() && idOrMac != state.lastId) {
                state.lastId = idOrMac
            state.rotatingMacCount += 1
        }

        state.lastSeenMs = now
        state.lastRssi = rssi
        state.rawFrame = rawHex

        onTrackerUpdate(
            DetectedTracker(
                id = "AIRTAG_$signature",
                logicalId = "AIRTAG_$signature",
                kind = TrackerKind.AIRTAG,
                address = idOrMac,
                rssi = rssi,
                distanceMeters = estimateDistance(rssi),
                lastSeenMs = now,
                signature = signature,
                rawFrame = rawHex,
                rotatingMacCount = state.rotatingMacCount
            )
        )
    }

    private fun isAirTagManufacturerFrame(mfg: ByteArray): Boolean {
        if (mfg.size < 20 || mfg.size > 28) return false
        val t0 = mfg[0].toInt() and 0xFF
        val t1 = mfg[1].toInt() and 0xFF
        return (t0 == 0x12 && t1 == 0x19) ||
                (t0 == 0x10 && t1 == 0x05) ||
                (t0 == 0x12 && t1 == 0x02)
    }

    private fun buildSettings(): ScanSettings =
        ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setReportDelay(0L)
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
