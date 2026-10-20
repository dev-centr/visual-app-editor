package org.devcentr.vae.rpc

/**
 * Minimal JSON reader/writer for the service protocol. Values are
 * Map<String, Any?>, List<Any?>, String, Long, Double, Boolean or null.
 * Kept dependency-free so the plugin bundles no third-party library.
 */
object Json {
    fun write(v: Any?): String = StringBuilder().also { write(v, it) }.toString()

    private fun write(v: Any?, sb: StringBuilder) {
        when (v) {
            null -> sb.append("null")
            is String -> quote(v, sb)
            is Boolean -> sb.append(v)
            is Int, is Long, is Short -> sb.append(v.toString())
            is Number -> {
                val d = v.toDouble()
                if (d == Math.floor(d) && !d.isInfinite() && Math.abs(d) < 1e15) sb.append(d.toLong()) else sb.append(d)
            }
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, x) in v) {
                    if (!first) sb.append(',')
                    first = false
                    quote(k.toString(), sb)
                    sb.append(':')
                    write(x, sb)
                }
                sb.append('}')
            }
            is Iterable<*> -> {
                sb.append('[')
                var first = true
                for (x in v) {
                    if (!first) sb.append(',')
                    first = false
                    write(x, sb)
                }
                sb.append(']')
            }
            is Array<*> -> write(v.toList(), sb)
            else -> quote(v.toString(), sb)
        }
    }

    private fun quote(s: String, sb: StringBuilder) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                else -> if (c < ' ') sb.append(String.format("\\u%04x", c.code)) else sb.append(c)
            }
        }
        sb.append('"')
    }

    fun parse(text: String): Any? {
        val p = Parser(text)
        val v = p.value()
        p.ws()
        if (p.i != text.length) throw IllegalArgumentException("Trailing data at ${p.i}")
        return v
    }

    private class Parser(val s: String) {
        var i = 0

        fun ws() {
            while (i < s.length && s[i].isWhitespace()) i++
        }

        fun value(): Any? {
            ws()
            if (i >= s.length) throw IllegalArgumentException("Unexpected end of JSON")
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> if (c == '-' || c.isDigit()) num() else throw IllegalArgumentException("Unexpected '$c' at $i")
            }
        }

        private fun lit(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) throw IllegalArgumentException("Bad literal at $i")
            i += word.length
            return v
        }

        private fun num(): Any {
            val start = i
            if (s[i] == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] in ".eE+-")) i++
            val t = s.substring(start, i)
            return if (t.any { it in ".eE" }) t.toDouble() else t.toLong()
        }

        private fun str(): String {
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) throw IllegalArgumentException("Unterminated string")
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        val e = s[i++]
                        when (e) {
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'u' -> {
                                sb.append(s.substring(i, i + 4).toInt(16).toChar())
                                i += 4
                            }
                            else -> sb.append(e)
                        }
                    }
                    else -> sb.append(c)
                }
            }
        }

        private fun arr(): List<Any?> {
            i++
            val out = ArrayList<Any?>()
            ws()
            if (s[i] == ']') {
                i++
                return out
            }
            while (true) {
                out.add(value())
                ws()
                when (s[i++]) {
                    ',' -> continue
                    ']' -> return out
                    else -> throw IllegalArgumentException("Expected , or ] at ${i - 1}")
                }
            }
        }

        private fun obj(): Map<String, Any?> {
            i++
            val out = LinkedHashMap<String, Any?>()
            ws()
            if (s[i] == '}') {
                i++
                return out
            }
            while (true) {
                ws()
                val k = str()
                ws()
                if (s[i++] != ':') throw IllegalArgumentException("Expected : at ${i - 1}")
                out[k] = value()
                ws()
                when (s[i++]) {
                    ',' -> continue
                    '}' -> return out
                    else -> throw IllegalArgumentException("Expected , or } at ${i - 1}")
                }
            }
        }
    }
}

@Suppress("UNCHECKED_CAST")
fun Any?.asMap(): Map<String, Any?> = this as? Map<String, Any?> ?: emptyMap()

fun Any?.asList(): List<Any?> = this as? List<Any?> ?: emptyList()

fun Map<String, Any?>.str(k: String): String? = this[k] as? String

fun Map<String, Any?>.int(k: String): Int? = (this[k] as? Number)?.toInt()
