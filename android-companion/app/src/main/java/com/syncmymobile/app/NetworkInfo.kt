package com.syncmymobile.app

import java.net.Inet4Address
import java.net.NetworkInterface

object NetworkInfo {
    fun localAddresses(): List<String> {
        return NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { network -> network.inetAddresses.toList() }
            .filterIsInstance<Inet4Address>()
            .filterNot { it.isLoopbackAddress }
            .map { it.hostAddress }
            .distinct()
    }
}
