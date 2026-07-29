package com.sunmobility.asset_recovery_app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * In-app SIM call bridge (Rule 8a — Android only).
 *
 * Places the call on the device's own SIM with [Intent.ACTION_CALL], so the
 * agent never leaves the app to dial: one tap on "Start Call" and the line is
 * already ringing. The telephony stack is then watched so the call's duration
 * is measured by the OS rather than by an in-app stopwatch, and streamed back
 * to Dart as `dialing` → `active` → `ended`.
 *
 * Duration is measured OFF_HOOK → IDLE, which is what the platform exposes
 * without the sensitive READ_CALL_LOG permission. For an outgoing call the line
 * goes off-hook as soon as it is placed, so the reported seconds include the
 * ringing time before the customer picked up.
 */
class SimCallHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.sunmobility.asset_recovery_app/sim_call"
        const val EVENT_CHANNEL = "com.sunmobility.asset_recovery_app/sim_call/events"

        /** Request code for the CALL_PHONE / READ_PHONE_STATE grant. */
        private const val PERMISSION_REQUEST_CODE = 7311

        /**
         * Give up on a call that never reaches OFF_HOOK after this long — the
         * SIM rejected it, or a call-screening app swallowed the intent. Keeps
         * the UI from sitting on "Dialing…" forever.
         */
        private const val DIAL_TIMEOUT_MS = 45_000L
    }

    private val methodChannel =
        MethodChannel(messenger, METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
    private val eventChannel =
        EventChannel(messenger, EVENT_CHANNEL).also { it.setStreamHandler(this) }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val telephony: TelephonyManager? =
        activity.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager

    private var eventSink: EventChannel.EventSink? = null

    /** Non-null while a [requestPermissions] grant dialog is outstanding. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var stateListener: PhoneStateListener? = null

    /** Wall-clock millis the tracked call was placed at; 0 when none is live. */
    private var activeCallId = 0L
    private var activeNumber: String? = null

    /** `elapsedRealtime()` when the line went off-hook; 0 until it does. */
    private var offHookAt = 0L

    /** True once a non-IDLE state arrived, so the IDLE at registration time is
     *  not mistaken for the call already having ended. */
    private var sawOffHook = false

    private var dialTimeout: Runnable? = null

    /** Result of the most recent finished call, replayed by `lastCallResult`
     *  when Dart comes back to the foreground having missed the event. */
    private var lastResult: Map<String, Any?>? = null

    // --- MethodChannel ------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(hasTelephony())
            "permissions" -> result.success(permissionMap())
            "requestPermissions" -> requestPermissions(result)
            "placeCall" -> placeCall(call.argument<String>("number"), result)
            "lastCallResult" -> result.success(lastResult)
            "stopTracking" -> {
                // The UI gave up waiting (or measured the call itself); close the
                // tracked call out with whatever the platform saw so far.
                finishCall(elapsedSeconds())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasTelephony(): Boolean =
        telephony != null &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)

    private fun granted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** `call` gates dialing at all; `phoneState` only gates duration tracking. */
    private fun permissionMap(): Map<String, Boolean> = mapOf(
        "call" to granted(Manifest.permission.CALL_PHONE),
        "phoneState" to granted(Manifest.permission.READ_PHONE_STATE),
    )

    private fun requestPermissions(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("in_progress", "A permission request is already in progress", null)
            return
        }
        val missing = listOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_PHONE_STATE,
        ).filterNot { granted(it) }
        if (missing.isEmpty()) {
            result.success(permissionMap())
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    /** Forwarded from `MainActivity`. Returns true when it handled the code. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        @Suppress("UNUSED_PARAMETER") permissions: Array<out String>,
        @Suppress("UNUSED_PARAMETER") grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        // Re-read the real grant state rather than trusting grantResults, which
        // is empty when the dialog is dismissed without a choice.
        pendingPermissionResult?.success(permissionMap())
        pendingPermissionResult = null
        return true
    }

    // --- Placing the call ---------------------------------------------------

    private fun placeCall(rawNumber: String?, result: MethodChannel.Result) {
        val number = rawNumber?.trim()
        if (number.isNullOrEmpty()) {
            result.error("invalid_number", "No phone number supplied", null)
            return
        }
        if (!hasTelephony()) {
            result.error("unsupported", "This device has no telephony/SIM support", null)
            return
        }
        if (!granted(Manifest.permission.CALL_PHONE)) {
            result.error("permission_denied", "CALL_PHONE has not been granted", null)
            return
        }

        // Any previously tracked call is done the moment a new one starts.
        finishCall(elapsedSeconds())

        activeCallId = System.currentTimeMillis()
        activeNumber = number
        offHookAt = 0L
        sawOffHook = false

        val trackable = granted(Manifest.permission.READ_PHONE_STATE) && startListening()
        try {
            // Uri.fromParts escapes the number for us (`#` in USSD-style
            // numbers must not reach the dialer raw). No NEW_TASK flag: the
            // in-call screen stacks on our task so hanging up lands the agent
            // straight back on the Call Customer screen.
            activity.startActivity(
                Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null)),
            )
        } catch (e: SecurityException) {
            resetTracking()
            result.error("permission_denied", e.message, null)
            return
        } catch (e: Exception) {
            resetTracking()
            result.error("dial_failed", e.message ?: "Could not place the call", null)
            return
        }

        val callId = activeCallId
        if (trackable) armDialTimeout() else resetTracking()
        emit(callId, number, "dialing", 0)
        result.success(
            mapOf(
                "callId" to activeCallId.toString(),
                "number" to number,
                // False when READ_PHONE_STATE is denied: the call still goes
                // through, Dart just has to time it itself.
                "stateTracked" to trackable,
            ),
        )
    }

    // --- Call-state tracking ------------------------------------------------

    /** Returns false when the platform refused the listener (denied grant). */
    @Suppress("DEPRECATION")
    private fun startListening(): Boolean {
        if (stateListener != null) return true
        val manager = telephony ?: return false
        val listener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                onCallState(state)
            }
        }
        return try {
            manager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            stateListener = listener
            true
        } catch (_: SecurityException) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun stopListening() {
        val listener = stateListener ?: return
        stateListener = null
        try {
            telephony?.listen(listener, PhoneStateListener.LISTEN_NONE)
        } catch (_: SecurityException) {
            // Nothing to unwind — the listener was never really attached.
        }
    }

    private fun onCallState(state: Int) {
        if (activeCallId == 0L) return
        when (state) {
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (offHookAt == 0L) {
                    offHookAt = SystemClock.elapsedRealtime()
                    sawOffHook = true
                    cancelDialTimeout()
                    emit(activeCallId, activeNumber, "active", 0)
                }
            }
            // IDLE fires once at registration too — only an IDLE *after* the
            // line went off-hook means the agent hung up.
            TelephonyManager.CALL_STATE_IDLE -> if (sawOffHook) finishCall(elapsedSeconds())
        }
    }

    private fun elapsedSeconds(): Int {
        if (offHookAt == 0L) return 0
        return ((SystemClock.elapsedRealtime() - offHookAt) / 1000L).toInt()
    }

    private fun finishCall(durationSeconds: Int) {
        if (activeCallId == 0L) return
        val callId = activeCallId
        val number = activeNumber
        lastResult = mapOf(
            "callId" to callId.toString(),
            "number" to number,
            "state" to "ended",
            "durationSeconds" to durationSeconds,
            "connected" to sawOffHook,
        )
        resetTracking()
        emit(callId, number, "ended", durationSeconds)
    }

    private fun resetTracking() {
        cancelDialTimeout()
        stopListening()
        activeCallId = 0L
        activeNumber = null
        offHookAt = 0L
        sawOffHook = false
    }

    private fun armDialTimeout() {
        cancelDialTimeout()
        val timeout = Runnable {
            dialTimeout = null
            // Still stuck before OFF_HOOK — the call never got off the ground.
            if (activeCallId != 0L && offHookAt == 0L) finishCall(0)
        }
        dialTimeout = timeout
        mainHandler.postDelayed(timeout, DIAL_TIMEOUT_MS)
    }

    private fun cancelDialTimeout() {
        dialTimeout?.let { mainHandler.removeCallbacks(it) }
        dialTimeout = null
    }

    // --- EventChannel -------------------------------------------------------

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(callId: Long, number: String?, state: String, durationSeconds: Int) {
        val payload = mapOf(
            "callId" to callId.toString(),
            "number" to number,
            "state" to state,
            "durationSeconds" to durationSeconds,
        )
        // PhoneStateListener already runs on the main looper, but finishCall is
        // also reachable from placeCall/stopTracking — post either way so the
        // sink is only ever touched from the platform thread.
        mainHandler.post { eventSink?.success(payload) }
    }

    // --- Lifecycle ----------------------------------------------------------

    fun dispose() {
        cancelDialTimeout()
        stopListening()
        pendingPermissionResult = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
