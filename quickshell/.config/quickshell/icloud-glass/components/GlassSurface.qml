// GlassSurface.qml — material base "Liquid Glass" (API congelada, ver docs/CONTRACTS.md §5)
//
// Arquitectura de capas, de abajo arriba:
//   0) (nada) — el fondo ya está desenfocado por el COMPOSITOR (regla `blur` de Hyprland
//      sobre el namespace `quickshell:icloud-glass*`). Este componente no desenfoca nada.
//   1) capa plana de respaldo: color de tinte + relleno — SIEMPRE presente y SIEMPRE
//      visible, garantiza que el panel nunca se queda negro/invisible si el shader falla.
//   2) ShaderEffectSource + ShaderEffect (liquidglass.frag.qsb): refracción de borde,
//      aberración cromática sutil y highlight especular. Capa puramente aditiva sobre (1).
//      Se desactiva completamente si `refraction === 0`, si reducedMotion está activo,
//      o si el .qsb no está disponible (ver `shaderActive` más abajo).
//   3) borde interior de 1px con el color `stroke` de Config.
//   4) hijos (default property `content`), clipados al radio.
//   5) sombra exterior vía MultiEffect, intensidad según `elevation` (0..3).
//
// El sampler `source` del shader captura, mediante `recursive: true` en el
// ShaderEffectSource, lo que haya detrás de esta superficie DENTRO de la escena QML
// (p.ej. las imágenes de fondo en GlassDemo.qml). En GlassPanel, al ser una layer-shell
// surface sin contenido QML detrás (el wallpaper vive fuera de la escena, ya
// desenfocado por el compositor), esa captura será mayormente transparente; el efecto
// de lente se aplica entonces sobre la propia capa de tinte, produciendo el realce de
// borde/especular esperado sin necesidad de leer píxeles ajenos a nuestra ventana.
//
// Degradación: si el .qsb no carga, Qt Quick (RHI) simplemente no dibuja el nodo del
// ShaderEffect (no pinta negro ni opaco) — solo se pierde la capa (2), quedando visible
// la capa plana (1) + borde (3) + sombra (5). Ese camino se fuerza explícitamente con
// `refraction: 0` y se prueba en GlassDemo.

import QtQuick
import QtQuick.Effects
import "../services" as Services

Item {
    id: root

    // --- API congelada (docs/CONTRACTS.md §5) --------------------------------
    property real radius: 20
    property color tint: Services.Config.c ? Services.Config.c.surface : "#0E0E11"
    property real tintAlpha: Services.Config.c ? Services.Config.c.surfaceAlpha : 0.38
    property int elevation: 1        // 0..3
    property real refraction: 1.0    // 0..1.5; 0 desactiva el shader
    property bool specular: true
    property bool interactive: false

    default property alias content: contentItem.data

    // --- estado interno --------------------------------------------------------
    readonly property bool reducedMotion: Services.Config.reducedMotion === true
    readonly property color strokeColor: Services.Config.c ? Services.Config.c.stroke : "#FFFFFF"
    readonly property real strokeAlpha: Services.Config.c ? Services.Config.c.strokeAlpha : 0.14

    // El shader solo se activa cuando tiene sentido visualmente: con refraction 0 o
    // reducedMotion activo, ni siquiera se captura el fondo (ver `sourceItem` más
    // abajo) — cero coste. Si el .qsb no puede cargarse en tiempo de ejecución (falta
    // el fichero, por ejemplo si no se ejecutó build-shaders.sh), Qt Quick (RHI)
    // registra un aviso pero NO dibuja el nodo del ShaderEffect ni pinta negro/opaco:
    // simplemente no se ve esa capa y queda visible la (1) plana + (3) borde + (5)
    // sombra. Por eso no hace falta ninguna lógica de "detección de fallo" aquí: el
    // propio ShaderEffect, al fallar, se comporta como si `shaderActive` fuera false.
    readonly property bool shaderActive: refraction > 0 && !reducedMotion

    // posición de luz normalizada (0..1); sigue al ratón si interactive, si no
    // apunta a un highlight superior-centro fijo (look "Apple": luz cenital).
    property real lightTargetX: 0.5
    property real lightTargetY: 0.12
    property point lightPos: Qt.point(lightTargetX, lightTargetY)

    implicitWidth: 200
    implicitHeight: 120

    // --- (1) capa plana de respaldo --------------------------------------------
    Rectangle {
        id: flatBase
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        opacity: root.tintAlpha
        antialiasing: true
    }

    // --- (2) refracción / especular / tinte extra vía shader --------------------
    // ShaderEffectSource captura lo que hay "detrás" de root dentro de la escena QML
    // (recursive: true permite que root se sitúe dentro del propio árbol capturado
    // sin bucle infinito — Qt Quick reutiliza el frame anterior para ese nodo).
    ShaderEffectSource {
        id: bgSource
        anchors.fill: parent
        // Sin sourceItem no hay nada que capturar/renderizar: así evitamos el coste
        // de la captura por completo cuando la capa de shader no está activa
        // (ShaderEffectSource no tiene una propiedad `active`; esto logra lo mismo).
        sourceItem: root.shaderActive ? (root.parent ? root.parent : root) : null
        recursive: true
        hideSource: false
        live: true
        visible: false
        smooth: true
    }

    // Instancia directa (sin Loader/Component intermedio): así todas las referencias
    // a `root.*` de abajo resuelven de forma normal y no dependen de que el .qsb
    // exista para que el árbol de objetos se construya bien. Si `shaderActive` es
    // false, ni siquiera está visible ni consume tiempo de GPU (el nodo de escena se
    // omite por completo cuando `visible: false`).
    ShaderEffect {
        id: shaderItem
        anchors.fill: parent
        visible: root.shaderActive
        blending: true

        property var source: bgSource
        property vector2d size: Qt.vector2d(root.width, root.height)
        property real radius: root.radius
        property real refraction: root.refraction
        property real specularStrength: root.specular ? 0.85 : 0.0
        property vector2d lightPos: Qt.vector2d(root.lightPos.x, root.lightPos.y)
        property vector4d tintColor: Qt.vector4d(
            root.tint.r, root.tint.g, root.tint.b, root.tintAlpha * 0.35)
        property real chromatic: 0.6

        fragmentShader: Qt.resolvedUrl("../shaders/liquidglass.frag.qsb")
    }

    // Sigue la posición del ratón dentro de la superficie (solo si interactive).
    MouseArea {
        id: mouseTracker
        anchors.fill: parent
        enabled: root.interactive && root.specular
        hoverEnabled: root.interactive && root.specular
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onPositionChanged: (mouse) => {
            if (!root.interactive) return;
            const nx = Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width)));
            const ny = Math.max(0, Math.min(1, mouse.y / Math.max(1, root.height)));
            lightTargetX = nx;
            lightTargetY = ny;
        }
        onExited: {
            lightTargetX = 0.5;
            lightTargetY = 0.12;
        }
    }

    // Sigue al ratón con una interpolación tipo "muelle" (overshoot orgánico), no
    // lineal. Desactivada si no es interactivo o hay reducedMotion, en cuyo caso
    // lightPos salta directo al objetivo (que, sin interacción, es fijo).
    Behavior on lightPos {
        enabled: root.interactive && !root.reducedMotion
        SpringAnimation { spring: 2.4; damping: 0.32; epsilon: 0.001 }
    }

    // --- (3) borde interior de 1px ----------------------------------------------
    Rectangle {
        id: innerStroke
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.strokeColor.r, root.strokeColor.g, root.strokeColor.b, root.strokeAlpha)
        antialiasing: true
    }

    // --- (4) hijos, clipados al radio --------------------------------------------
    Item {
        id: clipContainer
        anchors.fill: parent
        clip: true

        Item {
            id: contentItem
            anchors.fill: parent
        }
    }

    // --- (5) sombra exterior por capas, según elevation (0..3) -------------------
    MultiEffect {
        anchors.fill: parent
        source: flatBase
        z: -1
        shadowEnabled: root.elevation > 0
        shadowColor: Qt.rgba(0, 0, 0, 0.45)
        shadowBlur: [0.0, 0.35, 0.55, 0.75][Math.max(0, Math.min(3, root.elevation))]
        shadowVerticalOffset: [0, 2, 6, 12][Math.max(0, Math.min(3, root.elevation))]
        shadowHorizontalOffset: 0
        shadowOpacity: [0.0, 0.22, 0.32, 0.42][Math.max(0, Math.min(3, root.elevation))]
        shadowScale: 1.0
        blurEnabled: false
        brightness: 0.0
        contrast: 0.0
        saturation: 0.0
    }
}
