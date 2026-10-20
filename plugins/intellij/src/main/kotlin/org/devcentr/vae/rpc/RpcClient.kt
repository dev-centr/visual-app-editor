package org.devcentr.vae.rpc

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

class RpcError(val code: Int, message: String) : RuntimeException(message)

/**
 * JSON-RPC 2.0 client with LSP-style `Content-Length` framing, the wire
 * format of `vae_service` (see docs/modules/ROOT/pages/protocol.adoc).
 */
class RpcClient(
    private val input: InputStream,
    private val output: OutputStream,
    private val onNotification: (method: String, params: Map<String, Any?>) -> Unit = { _, _ -> },
) : AutoCloseable {
    private val nextId = AtomicLong(1)
    private val pending = ConcurrentHashMap<Long, CompletableFuture<Any?>>()
    @Volatile private var closedReason: String? = null

    private val reader = Thread({ readLoop() }, "vae-rpc-reader").apply {
        isDaemon = true
        start()
    }

    fun request(method: String, params: Map<String, Any?> = emptyMap()): CompletableFuture<Any?> {
        val f = CompletableFuture<Any?>()
        closedReason?.let {
            f.completeExceptionally(RpcError(-32603, it))
            return f
        }
        val id = nextId.getAndIncrement()
        pending[id] = f
        try {
            send(mapOf("jsonrpc" to "2.0", "id" to id, "method" to method, "params" to params))
        } catch (e: Exception) {
            pending.remove(id)
            f.completeExceptionally(RpcError(-32603, "Send failed: ${e.message}"))
        }
        return f
    }

    fun notify(method: String, params: Map<String, Any?> = emptyMap()) {
        send(mapOf("jsonrpc" to "2.0", "method" to method, "params" to params))
    }

    @Synchronized
    private fun send(msg: Map<String, Any?>) {
        val body = Json.write(msg).toByteArray(Charsets.UTF_8)
        output.write("Content-Length: ${body.size}\r\n\r\n".toByteArray(Charsets.US_ASCII))
        output.write(body)
        output.flush()
    }

    private fun readLoop() {
        try {
            while (true) {
                val msg = readMessage() ?: break
                dispatch(Json.parse(msg).asMap())
            }
            fail("Service closed the connection")
        } catch (e: Exception) {
            fail("Service connection failed: ${e.message}")
        }
    }

    private fun dispatch(m: Map<String, Any?>) {
        val id = (m["id"] as? Number)?.toLong()
        val method = m.str("method")
        if (method != null && id == null) {
            onNotification(method, m["params"].asMap())
            return
        }
        if (method != null) {
            // Server-to-client requests are not used; answer politely.
            send(mapOf("jsonrpc" to "2.0", "id" to id, "error" to mapOf("code" to -32601, "message" to "Not supported")))
            return
        }
        val f = pending.remove(id ?: return) ?: return
        val err = m["error"]
        if (err != null) {
            val e = err.asMap()
            f.completeExceptionally(RpcError(e.int("code") ?: -32603, e.str("message") ?: "error"))
        } else {
            f.complete(m["result"])
        }
    }

    /** Reads one framed message, or null at end of stream. */
    private fun readMessage(): String? {
        var length = -1
        val line = ByteArrayOutputStream()
        while (true) {
            val b = input.read()
            if (b < 0) return null
            if (b == '\n'.code) {
                val h = line.toString(Charsets.US_ASCII).trimEnd('\r')
                line.reset()
                if (h.isEmpty()) {
                    if (length >= 0) break
                    continue
                }
                val colon = h.indexOf(':')
                if (colon > 0 && h.substring(0, colon).trim().equals("Content-Length", ignoreCase = true)) {
                    length = h.substring(colon + 1).trim().toInt()
                }
            } else {
                line.write(b)
            }
        }
        val buf = ByteArray(length)
        var off = 0
        while (off < length) {
            val n = input.read(buf, off, length - off)
            if (n < 0) return null
            off += n
        }
        return String(buf, Charsets.UTF_8)
    }

    private fun fail(reason: String) {
        if (closedReason == null) closedReason = reason
        for (f in pending.values) f.completeExceptionally(RpcError(-32603, closedReason!!))
        pending.clear()
    }

    val isClosed: Boolean get() = closedReason != null

    override fun close() {
        fail("Client closed")
        runCatching { output.close() }
        runCatching { input.close() }
    }
}
