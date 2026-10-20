package org.devcentr.vae

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.components.PersistentStateComponent
import com.intellij.openapi.components.Service
import com.intellij.openapi.components.State
import com.intellij.openapi.components.Storage

@Service(Service.Level.APP)
@State(name = "VisualAppEditorSettings", storages = [Storage("visual-app-editor.xml")])
class VaeSettings : PersistentStateComponent<VaeSettings.S> {
    class S {
        /** e.g. `dart run C:/code/.../packages/service/bin/vae_service.dart` or a compiled vae_service executable. */
        var serviceCommand: String = ""
        /** e.g. `node C:/code/.../adapters/react/dist/cli.js`; enables .tsx/.jsx files. */
        var reactAdapterCommand: String = ""
        var devicePreset: String = ""
    }

    private var s = S()
    override fun getState(): S = s
    override fun loadState(state: S) {
        s = state
    }

    companion object {
        fun get(): VaeSettings = ApplicationManager.getApplication().getService(VaeSettings::class.java)
    }
}
