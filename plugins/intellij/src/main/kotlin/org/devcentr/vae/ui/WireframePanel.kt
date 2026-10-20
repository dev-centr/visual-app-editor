package org.devcentr.vae.ui

import com.intellij.ui.JBColor
import com.intellij.util.ui.JBUI
import org.devcentr.vae.DevicePreset
import org.devcentr.vae.Node
import java.awt.BasicStroke
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.RenderingHints
import javax.swing.JPanel

/**
 * Structural preview: the widget tree as nested boxes inside the chosen device
 * size. It is not a renderer; live rendering stays with the desktop app and the
 * device_preview harness (see the spec).
 */
class WireframePanel : JPanel() {
    private var root: Node? = null
    private var device: DevicePreset? = null
    var selected: List<Int> = emptyList()
        set(v) {
            field = v
            repaint()
        }

    fun update(r: Node?, d: DevicePreset?) {
        root = r
        device = d
        repaint()
    }

    override fun paintComponent(g0: Graphics) {
        super.paintComponent(g0)
        val g = g0 as Graphics2D
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        val d = device ?: return
        val pad = JBUI.scale(16)
        val scale = minOf((width - 2 * pad).toDouble() / d.width, (height - 2 * pad - JBUI.scale(16)).toDouble() / d.height).coerceAtLeast(0.05)
        val w = (d.width * scale).toInt()
        val h = (d.height * scale).toInt()
        val x0 = (width - w) / 2
        val y0 = pad + JBUI.scale(16)
        g.color = JBColor.GRAY
        g.drawString("${d.label}  ${d.width}x${d.height}  (${d.mode})", x0, pad + JBUI.scale(10))
        g.stroke = BasicStroke(JBUI.scale(2).toFloat())
        g.drawRoundRect(x0, y0, w, h, JBUI.scale(16), JBUI.scale(16))
        g.stroke = BasicStroke(1f)
        root?.let { box(g, it, x0 + 4, y0 + 4, w - 8, h - 8, 0) }
    }

    private fun box(g: Graphics2D, n: Node, x: Int, y: Int, w: Int, h: Int, depth: Int) {
        if (w < 6 || h < 6) return
        val sel = n.path == selected
        g.color = if (sel) JBColor(0x4B8BFF, 0x7CC4FF) else JBColor(0xB0B0B0, 0x5A5A5A)
        g.drawRect(x, y, w, h)
        if (h > 14) {
            g.color = if (sel) JBColor(0x2A5FD0, 0xA9D4FF) else JBColor.GRAY
            g.drawString(n.label.take(w / 7), x + 3, y + 12)
        }
        if (n.children.isEmpty()) return
        val top = if (h > 30) 16 else 2
        val each = (h - top - 2) / n.children.size
        for ((i, c) in n.children.withIndex()) box(g, c, x + 4, y + top + i * each, w - 8, each - 2, depth + 1)
    }
}
