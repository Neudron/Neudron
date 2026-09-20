// STUB de Quickshell.Wayland.WlrLayershell — src/wayland/wlr_layershell/
// wlr_layershell.hpp confirma namespace/layer/keyboardFocus (documentados) Y
// también exclusiveZone/exclusionMode/margins/aboveWindows/focusable, que
// existen como Q_PROPERTY reales aunque la página de docs los oculta con
// QSDOC_HIDE (los mantiene en espejo con PanelWindowInterface). Este stub
// los incluye todos por fidelidad a la fuente C++, no solo a la doc pública.
//
// LÍMITE HONESTO (documentado también en el informe final): en Quickshell
// real, `WlrLayershell` es un *attached type* (QML_ATTACHED), registrado en
// C++ vía qmlAttachedPropertiesObject(). Eso es una función exclusivamente
// de C++: no existe forma de declarar un tipo "attached" desde QML puro.
// Verificado empíricamente en este arnés: intentar `Foo.prop: value` contra
// un tipo QML normal (no adjunto) produce el error real del motor
// "Non-existent attached object". Por eso este stub, aunque registra el tipo
// `WlrLayershell` para que `import Quickshell.Wayland` resuelva (útil para
// qmllint), NO permite instanciar en runtime GlassPanel.qml/shell.qml, que
// usan `WlrLayershell.namespace: ...` como propiedad adjunta. Ver el
// informe final: esos dos archivos solo se verificaron con qmllint y
// revisión manual contra el código fuente C++, no con este arnés offscreen.
import QtQml

QtObject {
    property int layer: 2 // WlrLayer.Top
    property string namespace_: "quickshell"
    property int keyboardFocus: 0 // WlrKeyboardFocus.None

    property var anchors: null
    property int exclusiveZone: 0
    property int exclusionMode: 2
    property var margins: null
    property bool aboveWindows: true
    property bool focusable: false
}
