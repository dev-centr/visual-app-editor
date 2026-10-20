package org.devcentr.vae.ui

import com.intellij.icons.AllIcons
import com.intellij.openapi.Disposable
import com.intellij.openapi.actionSystem.ActionManager
import com.intellij.openapi.actionSystem.ActionUpdateThread
import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.actionSystem.DefaultActionGroup
import com.intellij.openapi.actionSystem.ToggleAction
import com.intellij.openapi.fileEditor.OpenFileDescriptor
import com.intellij.openapi.project.DumbAwareAction
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.ComboBox
import com.intellij.openapi.ui.Messages
import com.intellij.openapi.ui.SimpleToolWindowPanel
import com.intellij.openapi.util.Disposer
import com.intellij.ui.CollectionListModel
import com.intellij.ui.DocumentAdapter
import com.intellij.ui.JBSplitter
import com.intellij.ui.SearchTextField
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBList
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.components.JBTabbedPane
import com.intellij.ui.table.JBTable
import com.intellij.ui.treeStructure.Tree
import com.intellij.util.ui.JBUI
import com.intellij.util.ui.tree.TreeUtil
import org.devcentr.vae.DevicePreset
import org.devcentr.vae.Node
import org.devcentr.vae.PropRow
import org.devcentr.vae.Props
import org.devcentr.vae.VaeProjectService
import org.devcentr.vae.ViewState
import org.devcentr.vae.WidgetSpec
import java.awt.BorderLayout
import java.awt.FlowLayout
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import javax.swing.JPanel
import javax.swing.ListSelectionModel
import javax.swing.event.DocumentEvent
import javax.swing.table.AbstractTableModel
import javax.swing.tree.DefaultMutableTreeNode
import javax.swing.tree.DefaultTreeModel
import javax.swing.tree.TreePath
import javax.swing.tree.TreeSelectionModel

class VaePanel(private val project: Project, private val svc: VaeProjectService, parent: Disposable) :
    SimpleToolWindowPanel(true, true), Disposable {

    private var s = ViewState()
    private var selected: List<Int> = emptyList()
    private var mode = "phone"
    private var updating = false

    private val pageCombo = ComboBox<String>()
    private val presetCombo = ComboBox<DevicePreset>()
    private val status = JBLabel().apply { border = JBUI.Borders.empty(2, 6) }
    private val treeModel = DefaultTreeModel(DefaultMutableTreeNode("—"))
    private val tree = Tree(treeModel).apply {
        isRootVisible = true
        selectionModel.selectionMode = TreeSelectionModel.SINGLE_TREE_SELECTION
    }
    private val props = PropsModel()
    private val propsTable = JBTable(props).apply { setShowGrid(false); emptyText.text = "Select a widget" }
    private val search = SearchTextField(false)
    private val paletteModel = CollectionListModel<WidgetSpec>()
    private val palette = JBList(paletteModel).apply {
        selectionMode = ListSelectionModel.SINGLE_SELECTION
        cellRenderer = object : com.intellij.ui.ColoredListCellRenderer<WidgetSpec>() {
            override fun customizeCellRenderer(list: javax.swing.JList<out WidgetSpec>, v: WidgetSpec?, index: Int, selected: Boolean, focus: Boolean) {
                if (v == null) return
                append(v.className)
                append("   ${v.category}", com.intellij.ui.SimpleTextAttributes.GRAYED_ATTRIBUTES)
            }
        }
        emptyText.text = "No toolkits loaded"
    }
    val preview = WireframePanel()

    init {
        Disposer.register(parent, this)
        toolbar = buildToolbar()
        val top = JPanel(BorderLayout()).apply {
            add(JBScrollPane(tree), BorderLayout.CENTER)
        }
        val tabs = JBTabbedPane().apply {
            addTab("Properties", JBScrollPane(propsTable))
            addTab("Toolbox", JPanel(BorderLayout()).apply {
                add(search, BorderLayout.NORTH)
                add(JBScrollPane(palette), BorderLayout.CENTER)
                add(JPanel(FlowLayout(FlowLayout.LEFT)).apply {
                    add(javax.swing.JButton("Insert into selection").apply { addActionListener { insertSelected() } })
                }, BorderLayout.SOUTH)
            })
            addTab("Preview", preview)
        }
        val split = JBSplitter(true, 0.5f).apply {
            firstComponent = top
            secondComponent = tabs
        }
        setContent(JPanel(BorderLayout()).apply {
            add(split, BorderLayout.CENTER)
            add(status, BorderLayout.SOUTH)
        })

        tree.addTreeSelectionListener {
            val n = (tree.lastSelectedPathComponent as? DefaultMutableTreeNode)?.userObject as? Node
            selected = n?.path ?: emptyList()
            showProps(n)
            preview.selected = selected
        }
        tree.addMouseListener(object : MouseAdapter() {
            override fun mouseClicked(e: MouseEvent) {
                if (e.clickCount == 2) revealSelected()
            }
        })
        palette.addMouseListener(object : MouseAdapter() {
            override fun mouseClicked(e: MouseEvent) {
                if (e.clickCount == 2) insertSelected()
            }
        })
        search.addDocumentListener(object : DocumentAdapter() {
            override fun textChanged(e: DocumentEvent) = fillPalette()
        })
        pageCombo.addActionListener { if (!updating) (pageCombo.selectedItem as? String)?.let { svc.selectPage(it) } }
        presetCombo.addActionListener { if (!updating) (presetCombo.selectedItem as? DevicePreset)?.let { svc.setDevice(it.id) } }
        svc.addListener(this) { render(it) }
    }

    private fun buildToolbar(): JPanel {
        val group = DefaultActionGroup().apply {
            add(object : DumbAwareAction("Refresh", "Re-read the file", AllIcons.Actions.Refresh) {
                override fun actionPerformed(e: AnActionEvent) = svc.refresh()
            })
            addSeparator()
            add(simple("Move Up", AllIcons.Actions.MoveUp) { move(-1) })
            add(simple("Move Down", AllIcons.Actions.MoveDown) { move(1) })
            add(simple("Wrap With…", AllIcons.Actions.Expandall) { wrap() })
            add(simple("Delete", AllIcons.General.Remove) { delete() })
            addSeparator()
            for ((m, icon) in listOf("phone" to AllIcons.Nodes.Plugin, "tablet" to AllIcons.Nodes.Module, "desktop" to AllIcons.Nodes.Desktop, "web" to AllIcons.General.Web)) {
                add(object : ToggleAction(m.replaceFirstChar { it.uppercase() }, "Device mode: $m", icon) {
                    override fun isSelected(e: AnActionEvent) = mode == m
                    override fun setSelected(e: AnActionEvent, state: Boolean) {
                        if (state) setMode(m)
                    }
                    override fun getActionUpdateThread() = ActionUpdateThread.EDT
                })
            }
        }
        val tb = ActionManager.getInstance().createActionToolbar("VisualAppEditor", group, true)
        tb.targetComponent = this
        return JPanel(BorderLayout()).apply {
            add(tb.component, BorderLayout.WEST)
            add(JPanel(FlowLayout(FlowLayout.LEFT, 4, 0)).apply {
                add(JBLabel("Page:"))
                add(pageCombo)
                add(JBLabel("Device:"))
                add(presetCombo)
            }, BorderLayout.CENTER)
        }
    }

    private fun simple(text: String, icon: javax.swing.Icon, f: () -> Unit): AnAction = object : DumbAwareAction(text, text, icon) {
        override fun actionPerformed(e: AnActionEvent) = f()
        override fun update(e: AnActionEvent) {
            e.presentation.isEnabled = currentNode() != null && (currentNode() != s.root || text.startsWith("Wrap"))
        }
        override fun getActionUpdateThread() = ActionUpdateThread.EDT
    }

    private val isJsx get() = s.relPath?.let { it.endsWith(".tsx") || it.endsWith(".jsx") } == true

    private fun render(st: ViewState) {
        val sameTree = st.file == s.file && st.page == s.page
        s = st
        updating = true
        try {
            pageCombo.model = javax.swing.DefaultComboBoxModel(st.pages.toTypedArray())
            pageCombo.selectedItem = st.page
            val cur = st.presets.firstOrNull { it.id == st.device }
            if (cur != null) mode = cur.mode
            fillPresets(cur)
        } finally {
            updating = false
        }
        status.text = st.error?.let { "<html><font color='#e06c6c'>${escape(it).replace("\n", "<br>")}</font></html>" } ?: st.status
        val rootNode = DefaultMutableTreeNode(st.root ?: (st.page ?: "—"))
        fun add(parent: DefaultMutableTreeNode, n: Node) {
            for (c in n.children) DefaultMutableTreeNode(c).also { parent.add(it); add(it, c) }
        }
        st.root?.let { add(rootNode, it) }
        treeModel.setRoot(rootNode)
        tree.cellRenderer = object : javax.swing.tree.DefaultTreeCellRenderer() {
            override fun getTreeCellRendererComponent(t: javax.swing.JTree?, v: Any?, sel: Boolean, exp: Boolean, leaf: Boolean, row: Int, focus: Boolean) =
                super.getTreeCellRendererComponent(t, ((v as? DefaultMutableTreeNode)?.userObject as? Node)?.label ?: v.toString(), sel, exp, leaf, row, focus)
        }
        TreeUtil.expandAll(tree)
        val keep = if (sameTree) selected else emptyList()
        selectPath(rootNode, keep)
        fillPalette()
        preview.update(st.root, st.presets.firstOrNull { it.id == st.device } ?: st.presets.firstOrNull { it.mode == mode })
    }

    private fun selectPath(root: DefaultMutableTreeNode, path: List<Int>) {
        val e = root.depthFirstEnumeration()
        var hit: DefaultMutableTreeNode = root
        while (e.hasMoreElements()) {
            val n = e.nextElement() as DefaultMutableTreeNode
            if ((n.userObject as? Node)?.path == path) hit = n
        }
        tree.selectionPath = TreePath(hit.path)
    }

    private fun fillPresets(cur: DevicePreset?) {
        val list = s.presets.filter { it.mode == mode }
        presetCombo.model = javax.swing.DefaultComboBoxModel(list.toTypedArray())
        presetCombo.selectedItem = cur?.takeIf { it.mode == mode } ?: list.firstOrNull()
    }

    private fun setMode(m: String) {
        mode = m
        val first = s.presets.firstOrNull { it.mode == m } ?: return
        svc.setDevice(first.id)
    }

    private fun fillPalette() {
        val q = search.text.trim().lowercase()
        paletteModel.replaceAll(s.palette.filter { q.isEmpty() || it.className.lowercase().contains(q) || it.category.lowercase().contains(q) }.sortedWith(compareBy({ it.category == "Other" }, { it.category }, { it.className })))
    }

    private fun currentNode(): Node? = s.root?.find(selected)

    private fun showProps(n: Node?) {
        if (n == null) {
            props.set(null, emptyList())
            return
        }
        val spec = s.palette.firstOrNull { it.className == n.type.substringBefore('.') }
        val rows = Props.rows(n, spec).toMutableList()
        val content = n.text ?: n.args.firstOrNull { it.name == null }?.source
        if (content != null || n.type == "Text") rows.add(0, PropRow(CONTENT, if (isJsx) "text" else "positional 0", false, null, content ?: "", false))
        props.set(n, rows)
    }

    private fun revealSelected() {
        val n = currentNode() ?: return
        val vf = s.file ?: return
        OpenFileDescriptor(project, vf, n.offset).navigate(true)
    }

    private fun insertSelected() {
        val spec = palette.selectedValue ?: return
        val snippet = spec.snippet ?: if (isJsx) "<${spec.className} />" else "${spec.className}()"
        val target = currentNode()?.path ?: s.root?.path ?: return
        svc.edit("Insert ${spec.className}", mapOf("op" to "insertChild", "path" to target, "snippet" to snippet))
    }

    private fun delete() = svc.edit("Delete", mapOf("op" to "removeNode", "path" to selected))

    private fun move(d: Int) {
        svc.edit("Move", mapOf("op" to "moveInList", "path" to selected, "delta" to d))
        if (selected.isNotEmpty()) selected = selected.dropLast(1) + (selected.last() + d)
    }

    private fun wrap() {
        val w = Messages.showInputDialog(project, "Wrap the selection with:", "Wrap With", null, if (isJsx) "div" else "Padding", null) ?: return
        val extra = if (!isJsx && w == "Padding") "padding: const EdgeInsets.all(8)" else ""
        val slot = if (isJsx || w in setOf("Column", "Row", "Stack", "ListView", "Wrap")) "children" else "child"
        svc.edit("Wrap", mapOf("op" to "wrapNode", "path" to selected, "wrapper" to w, "slot" to slot, "extraArgs" to extra))
    }

    private fun commit(row: PropRow, value: String) {
        val path = currentNode()?.path ?: return
        val v = value.trim()
        when {
            row.name == CONTENT -> svc.edit("Set text", if (isJsx) mapOf("op" to "setText", "path" to path, "value" to v) else mapOf("op" to "setPositional", "path" to path, "index" to 0, "value" to v))
            v.isEmpty() -> if (row.value.isNotEmpty()) svc.edit("Remove ${row.name}", mapOf("op" to "removeArgument", "path" to path, "name" to row.name))
            v != row.value -> svc.edit("Set ${row.name}", mapOf("op" to "setArgument", "path" to path, "name" to row.name, "value" to v))
        }
    }

    private inner class PropsModel : AbstractTableModel() {
        var rows: List<PropRow> = emptyList()
        fun set(n: Node?, r: List<PropRow>) {
            rows = r
            fireTableDataChanged()
        }
        override fun getRowCount() = rows.size
        override fun getColumnCount() = 3
        override fun getColumnName(c: Int) = listOf("Property", "Value", "Type").getOrElse(c) { "" }
        override fun isCellEditable(r: Int, c: Int) = c == 1
        override fun getValueAt(r: Int, c: Int): Any {
            val row = rows[r]
            return when (c) {
                0 -> row.name + if (row.required) " *" else ""
                1 -> row.value // blank when unset; never the type name
                else -> row.type + (row.default?.let { "  = $it" } ?: "")
            }
        }
        override fun setValueAt(v: Any?, r: Int, c: Int) {
            if (c == 1) commit(rows[r], v?.toString() ?: "")
        }
    }

    override fun dispose() {}

    companion object {
        const val CONTENT = "(content)"
        private fun escape(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    }
}
