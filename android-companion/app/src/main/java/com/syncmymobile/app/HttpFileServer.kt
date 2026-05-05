package com.syncmymobile.app

import android.content.Context
import android.net.Uri
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class HttpFileServer(
    private val context: Context,
    private val index: FileIndex,
    private val port: Int,
) {
    private val running = AtomicBoolean(false)
    private val workers = Executors.newCachedThreadPool()
    private var serverSocket: ServerSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        workers.submit {
            serverSocket = ServerSocket(port)
            while (running.get()) {
                try {
                    val socket = serverSocket?.accept() ?: break
                    workers.submit { handle(socket) }
                } catch (_: Exception) {
                    if (running.get()) Thread.sleep(100)
                }
            }
        }
    }

    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        workers.shutdownNow()
    }

    private fun handle(socket: Socket) {
        socket.use {
            val input = it.getInputStream().bufferedReader()
            val firstLine = input.readLine() ?: return
            while (true) {
                val line = input.readLine() ?: break
                if (line.isBlank()) break
            }

            val parts = firstLine.split(" ")
            if (parts.size < 2) {
                writeText(it, 400, "Bad Request")
                return
            }

            val path = parts[1]
            when {
                path == "/manifest" -> writeJson(it, index.manifestJson())
                path.startsWith("/file?") -> writeFile(it, queryParam(path, "id"))
                else -> writeText(it, 404, "Not Found")
            }
        }
    }

    private fun writeFile(socket: Socket, id: String?) {
        if (id.isNullOrBlank()) {
            writeText(socket, 400, "Missing id")
            return
        }

        if (id.startsWith("url:")) {
            writeUrlFile(socket, id.removePrefix("url:"))
            return
        }

        val uri = Uri.parse(id)
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r")
        if (descriptor == null) {
            writeText(socket, 404, "File not found")
            return
        }
        val inputStream = context.contentResolver.openInputStream(uri)
        if (inputStream == null) {
            descriptor.close()
            writeText(socket, 404, "File not found")
            return
        }

        descriptor.use {
            val length = it.statSize
            val output = BufferedOutputStream(socket.getOutputStream())
            val header = buildString {
                append("HTTP/1.1 200 OK\r\n")
                append("Content-Type: application/octet-stream\r\n")
                if (length >= 0) append("Content-Length: $length\r\n")
                append("Connection: close\r\n\r\n")
            }
            output.write(header.toByteArray(StandardCharsets.UTF_8))
            BufferedInputStream(inputStream).use { stream ->
                stream.copyTo(output, 256 * 1024)
            }
            output.flush()
        }
    }

    private fun writeUrlFile(socket: Socket, url: String) {
        val connection = openCloudConnection(url)
        val code = connection.responseCode
        if (code !in 200..299) {
            writeText(socket, 502, "Cloud link returned HTTP $code")
            return
        }

        val output = BufferedOutputStream(socket.getOutputStream())
        val length = connection.contentLengthLong
        val header = buildString {
            append("HTTP/1.1 200 OK\r\n")
            append("Content-Type: application/octet-stream\r\n")
            if (length >= 0) append("Content-Length: $length\r\n")
            append("Connection: close\r\n\r\n")
        }
        output.write(header.toByteArray(StandardCharsets.UTF_8))
        BufferedInputStream(connection.inputStream).use { stream ->
            stream.copyTo(output, 256 * 1024)
        }
        output.flush()
    }

    private fun openCloudConnection(initialUrl: String): HttpURLConnection {
        var current = initialUrl
        repeat(8) {
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 SyncMyMobile/0.1")
            connection.setRequestProperty("Accept", "application/octet-stream,*/*")
            val code = connection.responseCode
            if (code in 300..399) {
                val location = connection.getHeaderField("Location")
                if (!location.isNullOrBlank()) {
                    current = URL(URL(current), location).toString()
                    connection.disconnect()
                    return@repeat
                }
            }

            if (current.contains("drive.google.com/uc", ignoreCase = true)) {
                val confirm = Regex("""confirm=([0-9A-Za-z_]+)""").find(readSmallErrorOrBody(connection))?.groupValues?.getOrNull(1)
                val cookie = connection.getHeaderField("Set-Cookie")
                if (!confirm.isNullOrBlank() && !current.contains("confirm=", ignoreCase = true)) {
                    connection.disconnect()
                    current += if (current.contains("?")) "&confirm=$confirm" else "?confirm=$confirm"
                    val retry = URL(current).openConnection() as HttpURLConnection
                    retry.instanceFollowRedirects = false
                    retry.setRequestProperty("User-Agent", "Mozilla/5.0 SyncMyMobile/0.1")
                    if (!cookie.isNullOrBlank()) retry.setRequestProperty("Cookie", cookie)
                    return retry
                }
            }
            return connection
        }
        return URL(current).openConnection() as HttpURLConnection
    }

    private fun readSmallErrorOrBody(connection: HttpURLConnection): String {
        return try {
            val stream = if (connection.responseCode in 200..399) connection.inputStream else connection.errorStream
            stream?.bufferedReader()?.use { it.readText().take(64 * 1024) } ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun writeJson(socket: Socket, body: String) {
        val bytes = body.toByteArray(StandardCharsets.UTF_8)
        val output = socket.getOutputStream()
        output.write(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                .toByteArray(StandardCharsets.UTF_8),
        )
        output.write(bytes)
        output.flush()
    }

    private fun writeText(socket: Socket, status: Int, body: String) {
        val bytes = body.toByteArray(StandardCharsets.UTF_8)
        val output = socket.getOutputStream()
        output.write(
            "HTTP/1.1 $status ${statusText(status)}\r\nContent-Type: text/plain\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                .toByteArray(StandardCharsets.UTF_8),
        )
        output.write(bytes)
        output.flush()
    }

    private fun statusText(status: Int): String = when (status) {
        400 -> "Bad Request"
        404 -> "Not Found"
        502 -> "Bad Gateway"
        else -> "OK"
    }

    private fun queryParam(path: String, name: String): String? {
        val query = path.substringAfter("?", "")
        return query.split("&")
            .mapNotNull {
                val pair = it.split("=", limit = 2)
                if (pair.size == 2) pair[0] to pair[1] else null
            }
            .firstOrNull { it.first == name }
            ?.second
            ?.let { URLDecoder.decode(it, "UTF-8") }
    }
}
