package com.example.offgrid

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.offgrid/nearby"
    private lateinit var channel: MethodChannel
    private lateinit var connectionsClient: ConnectionsClient
    private val STRATEGY = Strategy.P2P_STAR
    private val SERVICE_ID = "com.example.offgrid.service"

    private var myUsername: String = "User-${(1000..9999).random()}"
    // --- New map to store endpoint names ---
    private val discoveredEndpointNames = mutableMapOf<String, String>()
    // -------------------------------------

    private val TYPING_STATUS_START = "__typing_start__"
    private val TYPING_STATUS_STOP = "__typing_stop__"
    private val READ_RECEIPT_PREFIX = "__read__"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        connectionsClient = Nearby.getConnectionsClient(this)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startDiscovery" -> {
                    myUsername = call.argument("username") ?: myUsername
                    startDiscovery()
                    result.success(null)
                }
                "startAdvertising" -> {
                    myUsername = call.argument("username") ?: myUsername
                    startAdvertising()
                    result.success(null)
                }
                "connectToEndpoint" -> {
                    val endpointId = call.argument<String>("endpointId")
                    if (endpointId != null) {
                        connectionsClient.requestConnection(myUsername, endpointId, connectionLifecycleCallback)
                            .addOnSuccessListener { result.success("Connection request sent.") }
                            .addOnFailureListener { e -> result.error("CONNECT_ERROR", e.message, null) }
                    } else {
                        result.error("ARG_ERROR", "endpointId is null", null)
                    }
                }
                "sendMessage" -> {
                    val message = call.argument<String>("message")
                    val endpointId = call.argument<String>("endpointId")
                    if (message != null && endpointId != null) {
                        val payload = Payload.fromBytes(message.toByteArray(Charsets.UTF_8))
                        connectionsClient.sendPayload(endpointId, payload)
                        result.success("Message sent.")
                    } else {
                        result.error("ARG_ERROR", "Message or endpointId is null", null)
                    }
                }
                "stopAllEndpoints" -> {
                    connectionsClient.stopAllEndpoints()
                    result.success("Stopped all endpoints")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startDiscovery() {
        val options = DiscoveryOptions.Builder().setStrategy(STRATEGY).build()
        connectionsClient.startDiscovery(SERVICE_ID, endpointDiscoveryCallback, options)
            .addOnSuccessListener { println(">>> Discovery started") }
            .addOnFailureListener { e -> println(">>> Discovery failed: $e") }
    }

    private fun startAdvertising() {
        val options = AdvertisingOptions.Builder().setStrategy(STRATEGY).build()
        connectionsClient.startAdvertising(myUsername, SERVICE_ID, connectionLifecycleCallback, options)
            .addOnSuccessListener { println(">>> Advertising started") }
            .addOnFailureListener { e -> println(">>> Advertising failed: $e") }
    }

    // --- THIS CALLBACK IS UPDATED ---
    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            // Store the name when an endpoint is found
            discoveredEndpointNames[endpointId] = info.endpointName
            val endpoint = mapOf("id" to endpointId, "name" to info.endpointName)
            runOnUiThread {
                channel.invokeMethod("onEndpointFound", endpoint)
            }
        }
        override fun onEndpointLost(endpointId: String) {
            // Remove the name when an endpoint is lost
            discoveredEndpointNames.remove(endpointId)
            runOnUiThread {
                channel.invokeMethod("onEndpointLost", endpointId)
            }
        }
    }
    
    // --- THIS CALLBACK IS UPDATED ---
    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, connectionInfo: ConnectionInfo) {
            // Store the name when a connection is initiated (important for the advertiser)
            discoveredEndpointNames[endpointId] = connectionInfo.endpointName
            connectionsClient.acceptConnection(endpointId, payloadCallback)
        }
        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            when (result.status.statusCode) {
                ConnectionsStatusCodes.STATUS_OK -> {
                    connectionsClient.stopDiscovery()
                    connectionsClient.stopAdvertising()
                    // Now we can reliably get the name from our map
                    val endpointName = discoveredEndpointNames[endpointId] ?: "Unknown Device"
                    runOnUiThread {
                        channel.invokeMethod("onConnectionResult", mapOf("endpointId" to endpointId, "endpointName" to endpointName, "status" to "connected"))
                    }
                }
                ConnectionsStatusCodes.STATUS_CONNECTION_REJECTED -> {
                    runOnUiThread {
                         channel.invokeMethod("onConnectionResult", mapOf("endpointId" to endpointId, "status" to "rejected"))
                    }
                }
                ConnectionsStatusCodes.STATUS_ERROR -> {
                     runOnUiThread {
                         channel.invokeMethod("onConnectionResult", mapOf("endpointId" to endpointId, "status" to "error"))
                    }
                }
                else -> { /* Unknown status code */ }
            }
        }
        override fun onDisconnected(endpointId: String) {
             runOnUiThread {
                channel.invokeMethod("onDisconnected", endpointId)
            }
        }
    }
    
    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type == Payload.Type.BYTES) {
                val receivedBytes = payload.asBytes()!!
                val message = String(receivedBytes, Charsets.UTF_8)
                if (message.startsWith(READ_RECEIPT_PREFIX)) {
                    val messageId = message.removePrefix(READ_RECEIPT_PREFIX)
                    runOnUiThread {
                        channel.invokeMethod("onMessageRead", mapOf("endpointId" to endpointId, "messageId" to messageId))
                    }
                } else if (message == TYPING_STATUS_START || message == TYPING_STATUS_STOP) {
                    val isTyping = message == TYPING_STATUS_START
                    runOnUiThread {
                        channel.invokeMethod("onTypingStatusChanged", mapOf("endpointId" to endpointId, "isTyping" to isTyping))
                    }
                } else {
                    runOnUiThread {
                        channel.invokeMethod("onPayloadReceived", mapOf("endpointId" to endpointId, "message" to message))
                    }
                }
            }
        }
        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {}
    }
}