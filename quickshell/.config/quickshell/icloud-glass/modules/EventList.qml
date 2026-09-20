// EventList.qml — lista de eventos de un día y/o "próximos" (agente B1).
//
// Propiedad exclusiva de B1 (ver docs/CONTRACTS.md §7). Solo depende de
// services/ y components/ (congelados). Lista virtualizada (ListView), sin
// Repeater gigante, y sin ningún Timer de polling propio: toda la reactividad
// viene de las propiedades de DataStore (que ya reacciona a inotify).
//
// API pública:
//   property string date         ("YYYY-MM-DD"; "" = sin día concreto)
//   property bool showUpcoming   (añade la sección "Próximos")

import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../components" as Components

Item {
    id: root

    // --- API pública -------------------------------------------------------------
    property string date: ""
    property bool showUpcoming: false

    // --- escala fija del contrato (docs/CONTRACTS.md §4) --------------------------
    readonly property int spXS: 4
    readonly property int spS: 8
    readonly property int spM: 12
    readonly property int spL: 16
    readonly property int radiusChip: 12
    readonly property int radiusCard: 20
    readonly property int fontXS: 11
    readonly property int fontS: 13
    readonly property int fontM: 15

    implicitWidth: 320
    implicitHeight: 320

    // --- helpers de fecha ----------------------------------------------------------
    function pad2(n) { return n < 10 ? "0" + n : "" + n; }
    function isoDate(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()); }
    function dateFromIso(s) {
        var p = s.split("-");
        return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
    }

    readonly property string todayIso: isoDate(new Date())

    function dayHeaderLabel() {
        if (!root.date) return "";
        if (root.date === todayIso) return "Hoy";
        var d = dateFromIso(root.date);
        return Qt.formatDate(d, "d MMM");
    }

    // Día de referencia para calcular "Día N de M" en un evento multi-día:
    // el día que se está mostrando en esta sección concreta.
    function multiDayLabel(ev, contextIso) {
        if (!ev.startDate || !ev.endDate || ev.startDate === ev.endDate) return "";
        var start = dateFromIso(ev.startDate);
        var end = dateFromIso(ev.endDate);
        var totalDays = Math.round((end.getTime() - start.getTime()) / 86400000) + 1;
        var ctx = contextIso ? dateFromIso(contextIso) : start;
        var dayNum = Math.round((ctx.getTime() - start.getTime()) / 86400000) + 1;
        dayNum = Math.max(1, Math.min(totalDays, dayNum));
        return "Día " + dayNum + " de " + totalDays;
    }

    function durationLabel(ev) {
        if (ev.allDay) return "Todo el día";
        if (!ev.durationMinutes && ev.durationMinutes !== 0) return "";
        var mins = ev.durationMinutes;
        if (mins < 60) return mins + " min";
        var h = Math.floor(mins / 60);
        var m = mins % 60;
        return m === 0 ? (h + " h") : (h + " h " + m + " min");
    }

    function startTimeLabel(ev) {
        if (ev.allDay) return "Todo el día";
        if (!ev.start) return "";
        return Qt.formatDateTime(new Date(ev.start), "hh:mm");
    }

    // --- construcción del modelo plano (secciones + eventos) -----------------------
    function buildListModel() {
        var out = [];
        var dayEvents = root.date ? Services.DataStore.eventsOn(root.date) : [];

        if (root.date) {
            if (root.showUpcoming) {
                out.push({ kind: "header", id: "h-day", label: dayHeaderLabel() });
            }
            for (var i = 0; i < dayEvents.length; i++) {
                out.push({ kind: "event", id: "day-" + dayEvents[i].key, event: dayEvents[i], contextIso: root.date });
            }
        }

        if (root.showUpcoming) {
            var upcoming = Services.DataStore.upcoming(Services.Config.raw.upcomingCount);
            out.push({ kind: "header", id: "h-upcoming", label: "Próximos" });
            for (var j = 0; j < upcoming.length; j++) {
                var ev = upcoming[j];
                var ctx = (root.todayIso >= ev.startDate && root.todayIso <= ev.endDate) ? root.todayIso : ev.startDate;
                out.push({ kind: "event", id: "up-" + ev.key, event: ev, contextIso: ctx });
            }
        }
        return out;
    }

    // Depende de root.date/root.showUpcoming y, a través de eventsOn/upcoming,
    // de DataStore.events — se recalcula igual que las propiedades derivadas
    // de DataStore.qml.
    readonly property var listModel: buildListModel()

    readonly property bool isEmpty: {
        var hasDay = root.date && Services.DataStore.eventsOn(root.date).length > 0;
        var hasUpcoming = root.showUpcoming && Services.DataStore.upcoming(Services.Config.raw.upcomingCount).length > 0;
        return !hasDay && !hasUpcoming;
    }

    Components.States {
        id: states
        anchors.fill: parent
        kind: root.isEmpty ? Components.States.Empty : Components.States.None
        emptyMessage: "Sin eventos hoy"
        emptyIcon: "○" // círculo simple, no emoji

        ListView {
            id: listView
            anchors.fill: parent
            clip: true
            spacing: root.spS
            model: root.listModel
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            delegate: Loader {
                id: rowLoader
                required property var modelData
                required property int index
                width: listView.width
                sourceComponent: modelData.kind === "header" ? headerDelegate : eventDelegate

                // FALLO REAL encontrado y corregido (D1, tests/qml/tst_combined_panel.qml):
                // declarar `property var itemData: modelData` aquí NO llega a
                // la `required property var itemData` de headerDelegate/
                // eventDelegate más abajo — son objetos QML DISTINTOS (el
                // Loader y el ítem que instancia); un Loader no propaga sus
                // propias propiedades al componente cargado. El resultado
                // era, en cada fila, el warning de motor "Required property
                // itemData was not initialized" y la fila renderizándose sin
                // datos reales (itemData quedaba undefined). Reproducido de
                // forma aislada con qmltestrunner offscreen. La corrección
                // sigue el mismo patrón que ya usa RemindersWidget.qml
                // (propiedad ../modules/RemindersWidget.qml) para su propio
                // Loader: asignar explícitamente tras la carga.
                onLoaded: {
                    if (!item) return;
                    item.itemData = rowLoader.modelData;
                    if (item.hasOwnProperty("itemIndex")) item.itemIndex = rowLoader.index;
                }
            }
        }
    }

    Component {
        id: headerDelegate
        Text {
            // NO `required`: lo rellena Loader.onLoaded de más arriba, DESPUÉS
            // de que el ítem ya se ha creado — `required` solo se puede
            // satisfacer en la creación (mismo motivo por el que
            // RemindersWidget.qml usa `property var itemData` normal, no
            // required, para su propio patrón Loader+onLoaded).
            property var itemData
            text: itemData ? itemData.label : ""
            font.pixelSize: root.fontS
            font.bold: true
            font.letterSpacing: 0.3
            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
            topPadding: root.spS
            bottomPadding: root.spXS
        }
    }

    Component {
        id: eventDelegate
        Item {
            id: eventRoot
            // NO `required`: mismo motivo que en headerDelegate más arriba.
            property var itemData
            property int itemIndex: 0

            readonly property var ev: itemData ? itemData.event : null
            readonly property bool cancelled: !!(ev && ev.cancelled === true)

            implicitHeight: eventRow.implicitHeight + root.spS
            opacity: 0
            property real entranceY: 6

            transform: Translate { y: eventRoot.entranceY }

            Component.onCompleted: {
                if (Services.Config.reducedMotion) {
                    entranceFade.start();
                } else {
                    entranceStagger.start();
                }
            }

            SequentialAnimation {
                id: entranceStagger
                PauseAnimation { duration: eventRoot.itemIndex * 30 }
                ParallelAnimation {
                    NumberAnimation { target: eventRoot; property: "opacity"; to: 1.0; duration: 180; easing.type: Easing.OutQuad }
                    NumberAnimation { target: eventRoot; property: "entranceY"; to: 0; duration: 180; easing.type: Easing.OutQuad }
                }
            }

            NumberAnimation {
                id: entranceFade
                target: eventRoot
                property: "opacity"
                to: 1.0
                duration: 120
                easing.type: Easing.OutQuad
                onStarted: eventRoot.entranceY = 0
            }

            RowLayout {
                id: eventRow
                width: parent.width
                spacing: root.spS

                Rectangle {
                    Layout.preferredWidth: 4
                    Layout.fillHeight: true
                    Layout.minimumHeight: 32
                    radius: 2
                    color: eventRoot.ev.color || (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                    opacity: eventRoot.cancelled ? 0.4 : 1.0
                }

                Text {
                    // Ancho fijo (en vez de la característica OpenType `tnum`,
                    // no garantizada entre versiones de Qt): la columna de horas
                    // nunca cambia de ancho entre eventos.
                    Layout.preferredWidth: 56
                    text: root.startTimeLabel(eventRoot.ev)
                    font.pixelSize: root.fontXS
                    color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                    wrapMode: Text.WordWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: eventRoot.ev.title || ""
                        font.pixelSize: root.fontM
                        font.strikeout: eventRoot.cancelled
                        color: Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E"
                        opacity: eventRoot.cancelled ? 0.55 : 1.0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: root.spXS
                        visible: metaLabel.text.length > 0

                        Text {
                            id: metaLabel
                            text: {
                                var parts = [];
                                var dur = root.durationLabel(eventRoot.ev);
                                if (dur.length > 0) parts.push(dur);
                                var multi = root.multiDayLabel(eventRoot.ev, eventRoot.itemData.contextIso);
                                if (multi.length > 0) parts.push(multi);
                                if (eventRoot.cancelled) parts.push("Cancelado");
                                return parts.join(" · ");
                            }
                            font.pixelSize: root.fontXS
                            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
