package com.syncmymobile.app

import android.content.Context
import android.os.Build
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean

class UdpBeacon(
    private val context: Context,
    private val httpPort: Int,
) {
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        thread = Thread(::loop, "sync-beacon").also { it.start() }
    }

    fun stop() {
        running.set(false)
        thread?.interrupt()
    }

    private fun loop() {
        val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
        val payload = """{"app":"$APP_ID","deviceName":"${json(deviceName)}","port":$httpPort}"""
            .toByteArray(StandardCharsets.UTF_8)
        DatagramSocket().use { socket ->
            socket.broadcast = true
            while (running.get()) {
                broadcastAddresses().forEach { address ->
                    try {
                        val packet = DatagramPacket(payload, payload.size, address, DISCOVERY_PORT)
                        socket.send(packet)
                    } catch (_: Exception) {
                    }
                }
                try {
                    Thread.sleep(2000)
                } catch (_: InterruptedException) {
                    return
                }
            }
        }
    }

    private fun broadcastAddresses(): List<InetAddress> {
        val addresses = mutableListOf(InetAddress.getByName("255.255.255.255"))
        NetworkInterface.getNetworkInterfaces().toList().forEach { network ->
            if (!network.isUp || network.isLoopback) return@forEach
            network.interfaceAddresses
                .mapNotNull(InterfaceAddress::getBroadcast)
                .forEach { addresses.add(it) }
        }
        return addresses.distinctBy { it.hostAddress }
    }

    private fun json(value: String): String = value.replace("\\", "\\\\").replace("\"", "\\\"")
}
