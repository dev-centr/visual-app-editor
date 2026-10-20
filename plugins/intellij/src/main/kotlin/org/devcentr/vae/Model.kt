package org.devcentr.vae

import org.devcentr.vae.rpc.asList
import org.devcentr.vae.rpc.asMap
import org.devcentr.vae.rpc.int
import org.devcentr.vae.rpc.str

/** Mirrors vae_core TreeNode / WidgetSpec / DevicePreset JSON. */
data class Arg(val name: String?, val source: String)

data class Node(
    val type: String,
    val path: List<Int>,
    val slot: String?,
    val args: List<Arg>,
    val children: List<Node>,
    val offset: Int,
    val end: Int,
    val text: String?,
) {
    val label: String
        get() {
            val t = text?.trim()
            val head = if (slot != null && slot != "children") "$slot: $type" else type
            if (!t.isNullOrEmpty()) return "$head \"${t.take(40)}\""
            val first = args.firstOrNull { it.name == null }?.source
            if (first != null && first.length >= 2 && (first.startsWith("'") || first.startsWith("\""))) {
                return "$head \"${first.substring(1, first.length - 1).take(40)}\""
            }
            return head
        }

    /** Looks a node up by its own path (adapters differ in how the root's path is numbered). */
    fun find(p: List<Int>): Node? {
        if (path == p) return this
        for (c in children) c.find(p)?.let { return it }
        return null
    }

    fun deepest(offset: Int): Node? {
        if (offset < this.offset || offset > end) return null
        for (c in children) c.deepest(offset)?.let { return it }
        return this
    }

    companion object {
        fun from(j: Any?): Node {
            val m = j.asMap()
            return Node(
                type = m.str("type") ?: "?",
                path = m["path"].asList().map { (it as Number).toInt() },
                slot = m.str("slot"),
                args = m["args"].asList().map { a -> a.asMap().let { Arg(it.str("name"), it.str("source") ?: "") } },
                children = m["children"].asList().map { from(it) },
                offset = m.int("offset") ?: 0,
                end = m.int("end") ?: 0,
                text = m.str("text"),
            )
        }
    }
}

data class Param(val name: String, val type: String, val named: Boolean, val required: Boolean, val default: String?)

data class WidgetSpec(val className: String, val toolkit: String, val category: String, val params: List<Param>, val snippet: String?, val doc: String?) {
    companion object {
        fun from(j: Any?): WidgetSpec {
            val m = j.asMap()
            return WidgetSpec(
                className = m.str("class") ?: "?",
                toolkit = m.str("toolkit") ?: "",
                category = m.str("category") ?: "Other",
                params = m["params"].asList().map { p ->
                    p.asMap().let { Param(it.str("name") ?: "", it.str("type") ?: "", it["named"] as? Boolean ?: true, it["required"] as? Boolean ?: false, it.str("default")) }
                },
                snippet = m.str("snippet"),
                doc = m.str("doc"),
            )
        }
    }
}

data class DevicePreset(val id: String, val label: String, val mode: String, val width: Int, val height: Int) {
    override fun toString() = "$label  ${width}x$height"

    companion object {
        fun from(j: Any?): DevicePreset {
            val m = j.asMap()
            return DevicePreset(m.str("id") ?: "", m.str("label") ?: "", m.str("mode") ?: "phone", m.int("width") ?: 0, m.int("height") ?: 0)
        }
    }
}

/** One property row: parameter metadata merged with the node's current value (blank when unset). */
data class PropRow(val name: String, val type: String, val required: Boolean, val default: String?, val value: String, val named: Boolean)

object Props {
    fun rows(node: Node, spec: WidgetSpec?): List<PropRow> {
        val out = ArrayList<PropRow>()
        val seen = HashSet<String>()
        for (p in spec?.params.orEmpty()) {
            if (!p.named) continue
            val cur = node.args.firstOrNull { it.name == p.name }?.source ?: ""
            out += PropRow(p.name, p.type, p.required, p.default, cur, true)
            seen += p.name
        }
        for (a in node.args) {
            val n = a.name ?: continue
            if (n in seen) continue
            out += PropRow(n, "", false, null, a.source, true)
        }
        return out
    }
}
