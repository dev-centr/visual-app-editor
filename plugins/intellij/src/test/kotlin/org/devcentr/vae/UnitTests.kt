package org.devcentr.vae

import org.devcentr.vae.rpc.Json
import org.devcentr.vae.rpc.RpcClient
import org.devcentr.vae.rpc.RpcError
import org.devcentr.vae.rpc.asMap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

class JsonTest {
    @Test fun roundTrip() {
        val v = mapOf("a" to listOf(1L, 2.5, true, null, "q\"\n\u0001é"), "b" to emptyMap<String, Any?>(), "c" to emptyList<Any?>())
        assertEquals(v, Json.parse(Json.write(v)))
        assertEquals("""{"x":3}""", Json.write(mapOf("x" to 3.0)))
        assertEquals("€", Json.parse("\"\\u20ac\""))
    }

    @Test fun rejectsGarbage() {
        try {
            Json.parse("{\"a\":1} x")
            fail()
        } catch (_: IllegalArgumentException) {
        }
    }
}

class TextDiffTest {
    @Test fun minimal() {
        val a = "Text('a'),\nText('b'),\n"
        val b = "Text('a'),\nText('B'),\n"
        val c = TextDiff.minimal(a, b)!!
        assertEquals(TextChange(17, 18, "B"), c)
        assertEquals(b, TextDiff.apply(a, c))
        assertNull(TextDiff.minimal(a, a))
        for ((x, y) in listOf("" to "abc", "abc" to "", "aaa" to "aaaa", "abcabc" to "abc")) assertEquals(y, TextDiff.apply(x, TextDiff.minimal(x, y)!!))
    }
}

class ServiceCommandTest {
    @Test fun splitsQuotes() {
        assertEquals(listOf("C:\\Program Files\\dart.exe", "run", "a b.dart"), ServiceCommand.split("\"C:\\Program Files\\dart.exe\" run \"a b.dart\""))
        assertEquals(listOf("dart", "run", "x"), ServiceCommand.split("  dart   run x "))
    }

    @Test fun wrapsBatchShimsOnWindows() {
        val dir = createTempDirectory()
        File(dir, "dart.bat").writeText("@echo off")
        val argv = ServiceCommand.argv("dart run svc.dart", windows = true, path = dir.path, pathExt = ".EXE;.BAT")
        assertEquals(listOf("cmd.exe", "/c", File(dir, "dart.bat").path, "run", "svc.dart"), argv)
        assertEquals(listOf("node", "cli.js"), ServiceCommand.argv("node cli.js", windows = false, path = dir.path, pathExt = null))
    }

    private fun createTempDirectory() = kotlin.io.path.createTempDirectory("vae").toFile()
}

class PropsTest {
    @Test fun emptyFieldsAreBlankNotTypeNames() {
        val node = Node.from(Json.parse("""{"type":"Container","path":[0],"args":[{"name":"color","source":"Colors.red"},{"name":"extra","source":"1"}],"children":[],"offset":0,"end":5}"""))
        val spec = WidgetSpec.from(Json.parse("""{"class":"Container","toolkit":"widgets","params":[{"name":"color","type":"Color?"},{"name":"padding","type":"EdgeInsetsGeometry?","default":"null"},{"name":"child","type":"Widget?"}]}"""))
        val rows = Props.rows(node, spec)
        assertEquals(listOf("color", "padding", "child", "extra"), rows.map { it.name })
        assertEquals("Colors.red", rows[0].value)
        assertEquals("", rows[1].value)
        assertEquals("", rows[2].value)
        assertEquals("Container", node.label)
        assertEquals(node, node.find(listOf(0)))
        assertNull(node.find(emptyList()))
    }
}

class RpcClientTest {
    private fun frame(json: String): ByteArray {
        val b = json.toByteArray()
        return "Content-Length: ${b.size}\r\n\r\n".toByteArray() + b
    }

    @Test fun requestsResponsesNotificationsAndErrors() {
        val toClient = PipedOutputStream()
        val clientIn = PipedInputStream(toClient, 1 shl 16)
        val sent = ByteArrayOutputStream()
        val notes = mutableListOf<String>()
        val c = RpcClient(clientIn, sent) { m, p -> synchronized(notes) { notes += "$m:${p["file"]}" } }
        val f1 = c.request("initialize", mapOf("clientName" to "t"))
        val f2 = c.request("document/edit")
        toClient.write(frame("""{"jsonrpc":"2.0","method":"document/changed","params":{"file":"a.dart"}}"""))
        toClient.write(frame("""{"jsonrpc":"2.0","id":2,"error":{"code":-32020,"message":"rejected"}}"""))
        toClient.write(frame("""{"jsonrpc":"2.0","id":1,"result":{"ok":true,"s":"ü"}}"""))
        toClient.flush()
        assertEquals(mapOf("ok" to true, "s" to "ü"), f1.get(5, TimeUnit.SECONDS).asMap())
        try {
            f2.get(5, TimeUnit.SECONDS)
            fail()
        } catch (e: ExecutionException) {
            assertEquals(-32020, (e.cause as RpcError).code)
        }
        Thread.sleep(50)
        assertEquals(listOf("document/changed:a.dart"), synchronized(notes) { notes.toList() })
        val wire = sent.toString(Charsets.UTF_8)
        assertTrue(wire.startsWith("Content-Length: "))
        assertTrue(wire.contains("\"method\":\"initialize\""))
        // Closing the stream fails pending requests instead of hanging.
        val f3 = c.request("project/pages")
        toClient.close()
        try {
            f3.get(5, TimeUnit.SECONDS)
            fail()
        } catch (e: ExecutionException) {
            assertTrue(e.cause!!.message!!.contains("closed"))
        }
    }
}
