// GlassPanel.qml — envoltorio de PanelWindow (Quickshell) para el panel icloud-glass.
//
// IMPORTANTE — namespace y blur del compositor:
// El `namespace` de este PanelWindow se establece como `"icloud-glass" + suffix`. En
// tiempo de ejecución, Quickshell antepone su propio prefijo y el namespace EFECTIVO
// que ve Hyprland es `quickshell:icloud-glass...`. La regla de Hyprland que aplica
// `blur` al fondo de este panel hace match sobre `quickshell:icloud-glass*` — si se
// cambia el prefijo aquí, hay que avisar a A1/B3 para que actualicen esa regla en
// `hypr/`. Este componente NO gestiona el blur: eso es 100% responsabilidad del
// compositor; GlassSurface solo añade refracción/tinte/especular por encima.
//
// Comportamiento:
//   - `visible: false` mientras está cerrado: una layer-shell surface invisible no
//     captura clicks ni bloquea el foco de lo que hay debajo.
//   - Foco de teclado solo mientras está abierto; se devuelve automáticamente al cerrar
//     (Quickshell retira el foco de la surface al ocultarla).
//   - Abre con una animación de escala 0.96→1 + opacidad + desplazamiento vertical de
//     8px, entrada ease-out 240ms. La salida usa la MISMA curva pero acortada a ~65%
//     de la duración (160ms) para sentirse "rápida de cerrar". Ambas son
//     interrumpibles: cambiar `open` a mitad de una animación revierte suavemente.
//   - Con reducedMotion: solo fundido de opacidad, 120ms, sin escala ni desplazamiento.
//   - Se ancla al monitor de `Config.raw.monitor` (o al enfocado si es null) y se
//     posiciona según `Config.raw.position` (center | top-right | top-left |
//     bottom-right | bottom-left).
//   - Cierra con Esc y con clic fuera del panel.
//
// Uso típico (desde shell.qml / CombinedPanel.qml, propiedad del orquestador):
//   GlassPanel {
//       id: panel
//       content: MyWidget { }
//   }
//   Ipc.onToggle: panel.toggle()

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services" as Services

PanelWindow {
    id: root

    // --- API pública --------------------------------------------------------------
    property bool open: false
    default property alias content: surface.content
    property alias surface: surface

    // sufijo opcional para namespaces múltiples (p.ej. varios paneles independientes);
    // el namespace efectivo visto por Hyprland sigue empezando por "quickshell:icloud-glass".
    property string namespaceSuffix: ""

    function toggle() { open = !open; }
    function show() { open = true; }
    function hide() { open = false; }

    // --- geometría / anclaje ---------------------------------------------------------
    // Propiedades específicas de wlr-layer-shell: se configuran vía la interfaz
    // adjunta `WlrLayershell`, no como propiedades directas de PanelWindow.
    WlrLayershell.namespace: "icloud-glass" + namespaceSuffix
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    color: "transparent"

    // Si Config.raw.monitor nombra un monitor, lo usamos; si es null NO tocamos
    // `screen` en absoluto (el Binding de abajo queda inactivo) para que Quickshell
    // conserve su comportamiento por defecto (el monitor enfocado), tal como pide
    // el contrato ("o al enfocado").
    readonly property var configuredMonitor: Services.Config.raw ? Services.Config.raw.monitor : null
    Binding {
        target: root
        property: "screen"
        value: Quickshell.screens.find(s => s.name === root.configuredMonitor) || null
        when: !!root.configuredMonitor
    }

    // El panel ocupa toda la pantalla como superficie de posicionamiento; el
    // contenido visual real es `surface`, anclado dentro según Config.raw.position.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // visible: false cuando está cerrado → no captura clicks ni bloquea nada debajo.
    // Se mantiene visible unos instantes más mientras corre la animación de salida
    // (el id `closingAnimation`, aunque está declarado dentro de `surface.transitions`
    // más abajo, tiene alcance de documento QML y es accesible aquí).
    visible: open || closingAnimation.running

    readonly property bool reducedMotion: Services.Config.reducedMotion === true

    // Margen fijo respecto al borde de pantalla para las posiciones no centradas.
    readonly property int edgeMargin: 16

    // --- clic fuera para cerrar --------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.hide()
    }

    // --- Esc para cerrar -----------------------------------------------------------
    Item {
        anchors.fill: parent
        focus: root.open
        Keys.onEscapePressed: root.hide()
    }

    GlassSurface {
        id: surface
        radius: 28 // radio "panel" fijo, docs/CONTRACTS.md §4
        elevation: 3
        interactive: true

        // Tamaño del panel: ancho fijo (recortado al monitor si hace falta) y una
        // altura por defecto razonable. El contenido real (CombinedPanel, propiedad
        // del orquestador) puede sobreescribir `surface.height` si necesita más alto;
        // GlassSurface no se auto-dimensiona a sus hijos (no forma parte de su API
        // congelada), así que el dimensionado final es responsabilidad de quien use
        // GlassPanel.
        width: Math.min(420, root.width - root.edgeMargin * 2)
        height: 320

        // -- posicionamiento según Config.raw.position --------------------------------
        readonly property string pos: Services.Config.raw ? (Services.Config.raw.position || "center") : "center"

        x: {
            switch (pos) {
            case "top-left":
            case "bottom-left":
                return root.edgeMargin;
            case "top-right":
            case "bottom-right":
                return root.width - width - root.edgeMargin;
            default: // center
                return (root.width - width) / 2;
            }
        }
        y: {
            switch (pos) {
            case "top-left":
            case "top-right":
                return root.edgeMargin;
            case "bottom-left":
            case "bottom-right":
                return root.height - height - root.edgeMargin;
            default: // center
                return (root.height - height) / 2;
            }
        }

        // -- estado base de la animación (oculto) --------------------------------------
        scale: 0.96
        opacity: 0.0
        // el desplazamiento se aplica como offset adicional sobre `y`, vía transform,
        // para no pelear con el binding de posicionamiento de arriba.
        transform: Translate { id: entryOffset; y: 8 }

        states: [
            State {
                name: "shown"
                when: root.open
                PropertyChanges { target: surface; scale: 1.0; opacity: 1.0 }
                PropertyChanges { target: entryOffset; y: 0 }
            }
        ]

        transitions: [
            Transition {
                id: openTransition
                to: "shown"
                ParallelAnimation {
                    id: openingAnimation
                    NumberAnimation { target: surface; property: "scale"; duration: root.reducedMotion ? 120 : 240; easing.type: Easing.OutCubic }
                    NumberAnimation { target: surface; property: "opacity"; duration: root.reducedMotion ? 120 : 240; easing.type: Easing.OutCubic }
                    NumberAnimation { target: entryOffset; property: "y"; duration: root.reducedMotion ? 120 : 240; easing.type: Easing.OutCubic }
                }
            },
            Transition {
                id: closeTransition
                from: "shown"
                ParallelAnimation {
                    id: closingAnimation
                    NumberAnimation { target: surface; property: "scale"; duration: root.reducedMotion ? 120 : 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: surface; property: "opacity"; duration: root.reducedMotion ? 120 : 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: entryOffset; property: "y"; duration: root.reducedMotion ? 120 : 160; easing.type: Easing.OutCubic }
                }
            }
        ]

        // Con reducedMotion, se anula la escala y el desplazamiento (solo fundido):
        // en vez de complicar los States de arriba con ramas condicionales, forzamos
        // aquí los valores objetivo cuando reducedMotion está activo.
        Binding { target: surface; property: "scale"; value: 1.0; when: root.reducedMotion }
        Binding { target: entryOffset; property: "y"; value: 0; when: root.reducedMotion }
    }
}
