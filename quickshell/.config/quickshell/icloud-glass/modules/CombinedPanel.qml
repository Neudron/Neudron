// CombinedPanel.qml — el layout del panel: calendario, eventos del día
// seleccionado, próximos y recordatorios, en una sola columna.
//
// Es el único archivo que cose los módulos entre sí. Cada widget es autónomo y no
// conoce a los demás; aquí se comparte `selectedDate` entre CalendarWidget y
// EventList, y se coloca el banner de estado de sincronización, que es global al
// panel y no de un widget concreto.
//
// Va dentro de GlassPanel, que ya aporta la superficie de cristal del panel. Por eso
// aquí NO se envuelve nada en otro GlassSurface: anidar dos superficies duplicaría el
// shader y el tinte.

import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../components" as Components

Item {
    id: root

    // Día seleccionado, compartido por el calendario y la lista de eventos.
    // El dueño del estado es CalendarWidget: aquí solo se refleja. Poner un binding
    // de ida y otro de vuelta (`selectedDate: root...` + `onSelectedDateChanged:
    // root.selectedDate = ...`) crearía un bucle de bindings en QML.
    readonly property string selectedDate: calendar.selectedDate
    function selectDate(dateString) { calendar.selectedDate = dateString; }

    implicitWidth: 420
    implicitHeight: Math.min(column.implicitHeight + 2 * pad, maxHeight)

    // Altura máxima del panel: el contenido de recordatorios puede crecer sin límite,
    // así que a partir de aquí se hace scroll en vez de desbordar la pantalla.
    property int maxHeight: 900
    readonly property int pad: 16

    function todayString() {
        const d = new Date();
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    // "19 SÁBADO" — el encabezado del día seleccionado del mockup.
    function dayHeader(dateString) {
        if (!dateString)
            return "";
        const parts = dateString.split("-");
        const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        const weekday = Qt.formatDate(d, "dddd").toUpperCase();
        return Number(parts[2]) + " " + weekday;
    }

    function shiftDay(dateString, delta) {
        const parts = dateString.split("-");
        const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        d.setDate(d.getDate() + delta);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    readonly property var status: Services.DataStore.status
    readonly property bool isStale: status && (status.state === "stale" || status.state === "error")

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: root.pad
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Sin barra de scroll: un Flickable no la tiene por defecto, y adjuntar la de
        // QtQuick.Controls obligaría a importar Controls entero solo para ocultarla.

        ColumnLayout {
            id: column
            width: flick.width
            spacing: 16

            // --- banner de estado de sincronización -------------------------------
            // Global al panel: si iCloud falla, no tiene sentido repetir el aviso en
            // cada widget. Los datos en caché se siguen mostrando debajo.
            Components.States {
                id: syncBanner
                Layout.fillWidth: true
                visible: root.isStale
                kind: root.isStale
                    ? (root.status.state === "error"
                        ? Components.States.Error
                        : Components.States.Stale)
                    : Components.States.None
                errorMessage: (root.status && root.status.error)
                    ? root.status.error
                    : errorKindLabel(root.status ? root.status.errorKind : null)
                lastSyncOk: root.status ? root.status.lastSyncOk : null
                onRetry: Services.Actions.sync()
            }

            // --- calendario mensual ------------------------------------------------
            CalendarWidget {
                id: calendar
                Layout.fillWidth: true
            }

            // --- cabecera del día seleccionado: ◀  19 SÁBADO  ▶ ---------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                DayArrow {
                    text: "◀"
                    accessibleName: "Día anterior"
                    onActivated: root.selectDate(root.shiftDay(root.selectedDate, -1))
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.dayHeader(root.selectedDate)
                    color: Services.Config.c.onSurface
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                DayArrow {
                    text: "▶"
                    accessibleName: "Día siguiente"
                    onActivated: root.selectDate(root.shiftDay(root.selectedDate, 1))
                }
            }

            // --- eventos del día + próximos ----------------------------------------
            EventList {
                Layout.fillWidth: true
                date: root.selectedDate
                showUpcoming: true
            }

            // --- separador ----------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Services.Config.c.stroke
                opacity: Services.Config.c.strokeAlpha
            }

            // --- recordatorios -------------------------------------------------------
            Text {
                text: "RECORDATORIOS"
                color: Services.Config.c.onSurfaceMuted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }

            RemindersWidget {
                Layout.fillWidth: true
            }

            // --- pie: último sync ------------------------------------------------------
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: !!(root.status && root.status.lastSyncOk) && !root.isStale
                text: {
                    if (!root.status || !root.status.lastSyncOk)
                        return "";
                    const d = new Date(root.status.lastSyncOk);
                    return "Sincronizado a las " + Qt.formatTime(d, "HH:mm");
                }
                color: Services.Config.c.onSurfaceMuted
                font.pixelSize: 11
                opacity: 0.8
            }
        }
    }

    // Flecha de navegación de día. Área de click de 44px aunque el glifo sea pequeño,
    // como exige el contrato de accesibilidad.
    component DayArrow: Item {
        id: arrow
        property alias text: glyph.text
        property string accessibleName: ""
        signal activated()

        implicitWidth: 44
        implicitHeight: 44
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: arrow.accessibleName
        Accessible.onPressAction: arrow.activated()

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Services.Config.c.onSurface
            opacity: mouse.containsMouse ? 0.08 : 0
            Behavior on opacity {
                enabled: !Services.Config.reducedMotion
                NumberAnimation { duration: 120 }
            }
        }

        // Anillo de foco visible al navegar con teclado.
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "transparent"
            border.width: 2
            border.color: Services.Config.c.accent
            visible: arrow.activeFocus
        }

        Text {
            id: glyph
            anchors.centerIn: parent
            color: Services.Config.c.onSurfaceMuted
            font.pixelSize: 13
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arrow.activated()
        }

        Keys.onReturnPressed: arrow.activated()
        Keys.onSpacePressed: arrow.activated()
    }
}
