// STUB de Quickshell.ShellRoot — src/core/shell.hpp: también es
// ReloadPropagator (Scope), con una única propiedad extra de solo lectura
// `settings` que shell.qml de icloud-glass no usa.
import QtQml

QtObject {
    default property list<QtObject> children
    readonly property QtObject settings: null
}
