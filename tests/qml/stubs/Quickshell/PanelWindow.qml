// STUB de Quickshell.PanelWindow — fuente de verdad: src/window/panelinterface.hpp
// (PanelWindowInterface + WindowInterface). Confirmado ahí (NO en la página
// de documentación recortada, que oculta varias de estas propiedades con
// QSDOC_HIDE pero siguen siendo Q_PROPERTY reales):
//   anchors: Anchors { bool left, right, top, bottom }   (grouped property)
//   margins: Margins { ... }                              (grouped property)
//   exclusiveZone: int
//   exclusionMode: enum (Normal|Ignore|Auto)
//   aboveWindows: bool (default true)
//   focusable: bool (default false)
//   screen, color, visible, implicitWidth/Height, width/height  (WindowInterface)
//   default property: `data` (list<QObject>)
//
// LÍMITE HONESTO: PanelWindow real es respaldado, según la plataforma, por
// WlrLayershell (Wayland) o un backend X11, que además ajustan width/height
// automáticamente al tamaño del monitor cuando hay dos anchors opuestos
// activos ("the corresponding dimension will be forced to equal the screen
// width/height"). Este stub NO simula un compositor: width/height son
// propiedades normales con un valor por defecto fijo, no se recalculan solo
// por activar anchors. Por eso este arnés NO instancia GlassPanel.qml /
// shell.qml en tests de runtime — ver el informe final.
import QtQml

QtObject {
    id: root

    default property list<QtObject> data

    property PanelAnchorsGroup anchors: PanelAnchorsGroup {}
    property PanelMarginsGroup margins: PanelMarginsGroup {}

    property int exclusiveZone: 0
    property int exclusionMode: 2 // Auto
    property bool aboveWindows: true
    property bool focusable: false

    property bool visible: true
    property int implicitWidth: 0
    property int implicitHeight: 0
    property int width: 1920
    property int height: 1080
    property QtObject screen: null
    property color color: "white"
}
