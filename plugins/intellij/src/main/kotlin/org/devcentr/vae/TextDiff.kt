package org.devcentr.vae

/** The smallest single replacement turning [old] into [new]: replace old[start, oldEnd) with [text]. */
data class TextChange(val start: Int, val oldEnd: Int, val text: String)

object TextDiff {
    fun minimal(old: String, new: String): TextChange? {
        if (old == new) return null
        var p = 0
        val max = minOf(old.length, new.length)
        while (p < max && old[p] == new[p]) p++
        var so = old.length
        var sn = new.length
        while (so > p && sn > p && old[so - 1] == new[sn - 1]) {
            so--
            sn--
        }
        return TextChange(p, so, new.substring(p, sn))
    }

    fun apply(old: String, c: TextChange): String = old.substring(0, c.start) + c.text + old.substring(c.oldEnd)
}
