package org.devcentr.vae

import com.intellij.openapi.options.Configurable
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBTextField
import com.intellij.util.ui.FormBuilder
import javax.swing.JComponent
import javax.swing.JPanel

class VaeConfigurable : Configurable {
    private var service: JBTextField? = null
    private var react: JBTextField? = null
    private var panel: JPanel? = null

    override fun getDisplayName() = "Visual App Editor"

    override fun createComponent(): JComponent {
        val s = JBTextField()
        val r = JBTextField()
        service = s
        react = r
        s.emptyText.text = "auto: \$VAE_SERVICE, vae_service on PATH, or packages/service in the project"
        r.emptyText.text = "e.g. node C:/code/visual-app-editor/adapters/react/dist/cli.js"
        val p = FormBuilder.createFormBuilder()
            .addLabeledComponent("Service command:", s)
            .addComponentToRightColumn(JBLabel("<html>A compiled <code>vae_service</code> executable or <code>dart run &lt;repo&gt;/packages/service/bin/vae_service.dart</code>.</html>").apply { componentStyle = com.intellij.util.ui.UIUtil.ComponentStyle.SMALL })
            .addLabeledComponent("React adapter command:", r)
            .addComponentToRightColumn(JBLabel("Optional. Enables .tsx/.jsx files; its toolkits are read from ../toolkits next to dist/.").apply { componentStyle = com.intellij.util.ui.UIUtil.ComponentStyle.SMALL })
            .addComponentFillVertically(JPanel(), 0)
            .panel
        panel = p
        reset()
        return p
    }

    override fun isModified(): Boolean {
        val st = VaeSettings.get().state
        return service?.text != st.serviceCommand || react?.text != st.reactAdapterCommand
    }

    override fun apply() {
        val st = VaeSettings.get().state
        st.serviceCommand = service?.text?.trim() ?: ""
        st.reactAdapterCommand = react?.text?.trim() ?: ""
        for (p in com.intellij.openapi.project.ProjectManager.getInstance().openProjects) {
            p.getService(VaeProjectService::class.java)?.restart()
        }
    }

    override fun reset() {
        val st = VaeSettings.get().state
        service?.text = st.serviceCommand
        react?.text = st.reactAdapterCommand
    }

    override fun disposeUIResources() {
        service = null
        react = null
        panel = null
    }
}
