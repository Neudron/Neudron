// STUB no-op de QtQuick.Effects.MultiEffect.
//
// MultiEffect llegó en Qt 6.5 (QtQuick.Effects); este contenedor tiene Qt
// 6.4.2 y no existe paquete para instalarlo (verificado: no hay
// qml6-module-qtquick-effects en los repos disponibles). GlassSurface.qml
// SÍ usa la API real y documentada de Qt 6.5+ correctamente (esto no es un
// bug de icloud-glass, es una limitación de este contenedor de
// verificación) — por eso aquí no se "corrige" nada, solo se sustituye por
// un Item sin efecto visual que acepta las mismas propiedades para que el
// árbol QML se pueda instanciar y comprobar el resto de la lógica.
import QtQuick

Item {
    property var source: null
    property bool shadowEnabled: false
    property color shadowColor: "black"
    property real shadowBlur: 0.0
    property real shadowVerticalOffset: 0.0
    property real shadowHorizontalOffset: 0.0
    property real shadowOpacity: 1.0
    property real shadowScale: 1.0
    property bool blurEnabled: false
    property real blur: 0.0
    property real blurMax: 32
    property real brightness: 0.0
    property real contrast: 0.0
    property real saturation: 0.0
    property real colorizationColor: 0.0
    property real colorization: 0.0
}
