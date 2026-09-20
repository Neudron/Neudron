// STUB del value type `Anchors` de PanelWindow (src/window/panelinterface.hpp):
// Q_GADGET con 4 bools (left/right/top/bottom). Aquí se modela como un
// QtObject normal para poder usarse con la sintaxis de propiedad agrupada
// `anchors { top: true; ... }` que usa GlassPanel.qml.
import QtQml

QtObject {
    property bool left: false
    property bool right: false
    property bool top: false
    property bool bottom: false
}
