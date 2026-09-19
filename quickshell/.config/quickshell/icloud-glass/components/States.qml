// States.qml — los cuatro estados reutilizables de datos (loading/empty/error/stale)
// para los widgets del panel (CalendarWidget, RemindersWidget, EventList, ...).
//
// Uso típico dentro de un widget:
//
//   States {
//       kind: DataStore.ready
//           ? (DataStore.status.state === "stale" ? States.Stale : States.None)
//           : (loadingTimedOut ? States.Loading : States.None)
//       emptyMessage: "Sin eventos hoy"
//       errorMessage: DataStore.status.error || "Error desconocido"
//       lastSyncOk: DataStore.status.lastSyncOk
//       onRetry: Actions.sync()
//
//       // contenido normal del widget, va dentro como hijo:
//       ListView { ... }
//   }
//
// Todos los textos de error son frases en español que explican la causa (mapeadas
// desde `errorKind` de status.json: network | auth | server | config | tool | unknown).
// Contraste ≥4.5:1 sobre `Config.c.surface` en claro y oscuro (colores tomados de
// Config, nunca hardcodeados). Área táctil de los botones ≥44px.

import QtQuick
import QtQuick.Layouts
import "../services" as Services

Item {
    id: root

    // --- tipos de estado -------------------------------------------------------
    enum Kind { None, Loading, Empty, Error, Stale }

    property int kind: States.None

    // loading
    property int loadingDelayMs: 300 // el skeleton solo aparece si tarda más de esto

    // empty
    property string emptyMessage: "Sin elementos"
    property string emptyIcon: "✨" // ✨, sobreescribible por el widget

    // error — `errorMessage` ya debe venir en español (viene de status.error, o el
    // widget puede mapear errorKind con `errorKindLabel()` más abajo).
    property string errorMessage: "No se ha podido cargar la información."
    signal retry()

    // stale — banner discreto, no tapa los datos (se muestra "encima" pero fino).
    property var lastSyncOk: null // ISO 8601 o null

    // default property: el contenido real del widget (se muestra en `None`, y
    // también debajo del banner en `Stale`, que no lo tapa).
    default property alias content: contentSlot.data

    implicitWidth: 240
    implicitHeight: contentSlot.implicitHeight

    // Mapea errorKind (status.json) a una frase en español con la causa.
    function errorKindLabel(errKind) {
        switch (errKind) {
        case "network": return "No hay conexión de red.";
        case "auth": return "La contraseña de aplicación de iCloud no es válida o ha caducado.";
        case "server": return "Los servidores de iCloud no han respondido.";
        case "config": return "Falta configuración necesaria para sincronizar.";
        case "tool": return "Ha fallado una herramienta interna de sincronización.";
        default: return "Ha ocurrido un error inesperado.";
        }
    }

    // --- contenido normal del widget --------------------------------------------
    Item {
        id: contentSlot
        anchors.fill: parent
        visible: root.kind === States.None || root.kind === States.Stale
    }

    // --- banner "stale", discreto, no tapa los datos -----------------------------
    Rectangle {
        id: staleBanner
        visible: root.kind === States.Stale
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? staleRow.implicitHeight + 12 : 0
        radius: 12
        color: Services.Config.dark
            ? Qt.rgba(1, 1, 1, 0.10)
            : Qt.rgba(0, 0, 0, 0.06)
        border.width: 1
        border.color: Services.Config.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)

        RowLayout {
            id: staleRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
                text: "⚠️"
                font.pixelSize: 13
            }
            Text {
                Layout.fillWidth: true
                text: root.lastSyncOk
                    ? "Datos de la última sincronización correcta: " + Qt.formatDateTime(new Date(root.lastSyncOk), "d MMM, hh:mm")
                    : "Mostrando datos de una sincronización anterior."
                color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
        }
    }

    // --- loading: skeleton con shimmer, solo tras loadingDelayMs -----------------
    Item {
        id: loadingView
        anchors.fill: parent
        visible: false

        Timer {
            id: loadingDelayTimer
            interval: root.loadingDelayMs
            running: root.kind === States.Loading
            onTriggered: loadingView.visible = true
            onRunningChanged: if (!running) loadingView.visible = false
        }

        Column {
            anchors.fill: parent
            spacing: 8

            Repeater {
                model: 3
                delegate: Rectangle {
                    width: parent.width
                    height: 16
                    radius: 8
                    color: Services.Config.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                    // shimmer: gradiente que se desliza de izquierda a derecha en bucle
                    Rectangle {
                        id: shimmer
                        width: parent.width * 0.4
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop {
                                position: 0.5
                                color: Services.Config.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.55)
                            }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        x: -width
                        visible: !Services.Config.reducedMotion

                        SequentialAnimation on x {
                            running: loadingView.visible && !Services.Config.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: -shimmer.width
                                to: shimmer.parent ? shimmer.parent.width : 0
                                duration: 1100
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 250 }
                        }
                    }
                }
            }
        }
    }

    // --- empty --------------------------------------------------------------------
    ColumnLayout {
        id: emptyView
        visible: root.kind === States.Empty
        anchors.centerIn: parent
        spacing: 8
        width: Math.min(parent.width - 32, 280)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.emptyIcon
            font.pixelSize: 28
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.emptyMessage
            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    // --- error ----------------------------------------------------------------------
    ColumnLayout {
        id: errorView
        visible: root.kind === States.Error
        anchors.centerIn: parent
        spacing: 12
        width: Math.min(parent.width - 32, 280)

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "⚠️"
            font.pixelSize: 24
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.errorMessage
            color: Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E"
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: retryButton
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.max(retryLabel.implicitWidth + 32, 44)
            Layout.preferredHeight: 44 // área táctil mínima
            radius: 12
            color: retryArea.pressed
                ? Qt.darker(Services.Config.c ? Services.Config.c.accent : "#0A84FF", 1.15)
                : (Services.Config.c ? Services.Config.c.accent : "#0A84FF")

            Text {
                id: retryLabel
                anchors.centerIn: parent
                text: "Reintentar"
                color: "#FFFFFF"
                font.pixelSize: 15
                font.bold: true
            }

            MouseArea {
                id: retryArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.retry()
            }
        }
    }
}
