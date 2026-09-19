// CalendarWidget.qml — rejilla mensual del calendario (agente B1).
//
// Propiedad exclusiva de B1 (ver docs/CONTRACTS.md §7). No depende de nada
// fuera de services/ y components/ (ambos ya congelados/de solo lectura para
// mí). Toda la lógica de fechas se calcula aquí mismo en QML puro, sin
// dependencias externas.
//
// API pública:
//   property string selectedDate   ("YYYY-MM-DD"; cambia con selectedDateChanged,
//                                    la señal automática de la propiedad)
//
// Semana empieza en lunes (locale es-ES). La rejilla siempre reserva 6 filas
// x 7 columnas (42 celdas) aunque el mes visible quepa en 5, para que cambiar
// de mes nunca produzca un salto de layout.

import QtQuick
import QtQuick.Layouts
import "../services" as Services

Item {
    id: root

    // --- API pública (congelada por mí para el resto del panel) ---------------
    property string selectedDate: isoDate(new Date())

    // --- escala fija del contrato (docs/CONTRACTS.md §4); no son valores
    // mágicos, son los tokens documentados, simplemente Config no los expone
    // como propiedades (solo colores/tema/fuente están en Config.raw/Config.c).
    readonly property int spXS: 4
    readonly property int spS: 8
    readonly property int spM: 12
    readonly property int spL: 16
    readonly property int spXL: 24
    readonly property int spXXL: 32
    readonly property int radiusChip: 12
    readonly property int radiusCard: 20
    readonly property int fontXS: 11
    readonly property int fontS: 13
    readonly property int fontM: 15
    readonly property int fontL: 17

    readonly property int minCellSize: 44 // área de click mínima

    implicitWidth: 320
    implicitHeight: headerRow.implicitHeight + weekRow.implicitHeight
                    + gridHost.implicitHeight + spM * 3

    // --- reloj de "hoy", sin polling de archivos: un único timer que se
    // reprograma exactamente para el siguiente cambio de día. ------------------
    property date __todayDate: new Date()
    readonly property string todayIso: isoDate(__todayDate)

    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: {
            root.__todayDate = new Date();
            root.scheduleMidnightTick();
        }
    }

    Component.onCompleted: scheduleMidnightTick()

    function scheduleMidnightTick() {
        var now = new Date();
        var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5, 0);
        var ms = next.getTime() - now.getTime();
        midnightTimer.interval = Math.max(1000, ms);
        midnightTimer.start();
    }

    // --- mes visible actualmente (no tiene por qué coincidir con selectedDate) --
    property int viewYear: __todayDate.getFullYear()
    property int viewMonth: __todayDate.getMonth() + 1 // 1-12

    // --- cursor de teclado; independiente de selectedDate hasta pulsar Enter ---
    property string focusDate: selectedDate

    readonly property var monthNames: [
        "ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO",
        "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE"
    ]
    readonly property var dayInitials: ["L", "M", "X", "J", "V", "S", "D"]

    // --- helpers de fecha -------------------------------------------------------
    function pad2(n) { return n < 10 ? "0" + n : "" + n; }

    function isoDate(d) {
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
    }

    function isoFromYMD(y, m, d) {
        return y + "-" + pad2(m) + "-" + pad2(d);
    }

    function dateFromIso(s) {
        var p = s.split("-");
        return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
    }

    function daysInMonth(y, m) {
        // new Date(y, m, 0) = último día del mes m (1-based)
        return new Date(y, m, 0).getDate();
    }

    // lunes = 0 ... domingo = 6
    function mondayIndex(jsDay) { return (jsDay + 6) % 7; }

    // --- construcción de la rejilla (42 celdas fijas) ---------------------------
    function buildCells() {
        var firstOfMonth = new Date(viewYear, viewMonth - 1, 1);
        var leading = mondayIndex(firstOfMonth.getDay());
        var totalDays = daysInMonth(viewYear, viewMonth);

        var prevMonth = viewMonth === 1 ? 12 : viewMonth - 1;
        var prevYear = viewMonth === 1 ? viewYear - 1 : viewYear;
        var totalDaysPrev = daysInMonth(prevYear, prevMonth);

        var nextMonth = viewMonth === 12 ? 1 : viewMonth + 1;
        var nextYear = viewMonth === 12 ? viewYear + 1 : viewYear;

        var cells = [];
        for (var i = 0; i < leading; i++) {
            var dPrev = totalDaysPrev - leading + 1 + i;
            cells.push(makeCell(prevYear, prevMonth, dPrev, false));
        }
        for (var d = 1; d <= totalDays; d++) {
            cells.push(makeCell(viewYear, viewMonth, d, true));
        }
        var remaining = 42 - cells.length;
        for (var n = 1; n <= remaining; n++) {
            cells.push(makeCell(nextYear, nextMonth, n, false));
        }
        return cells;
    }

    function makeCell(y, m, d, inMonth) {
        var iso = isoFromYMD(y, m, d);
        var colors = Services.DataStore.colorsOn(iso);
        var dots = colors.slice(0, 3);
        if (colors.length > 3 && dots.length === 3) {
            dots = [dots[0], dots[1], "__neutral__"];
        }
        return {
            iso: iso,
            day: d,
            inMonth: inMonth,
            hasEvents: dots.length > 0,
            dots: dots
        };
    }

    // Depende implícitamente de viewYear/viewMonth (leídos dentro de
    // buildCells) y de DataStore.events (leído indirectamente vía colorsOn),
    // así que se recalcula solo cuando cualquiera de los dos cambia — mismo
    // patrón que usa DataStore.qml para sus propiedades derivadas.
    readonly property var cells: buildCells()

    // --- navegación de mes -------------------------------------------------------
    function changeViewMonth(delta) {
        var d = new Date(viewYear, viewMonth - 1 + delta, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth() + 1;
        if (!Services.Config.reducedMotion) monthFade.restart();
    }

    function goToday() {
        __todayDate = new Date();
        viewYear = __todayDate.getFullYear();
        viewMonth = __todayDate.getMonth() + 1;
        focusDate = todayIso;
        selectedDate = todayIso;
        if (!Services.Config.reducedMotion) monthFade.restart();
    }

    // --- navegación de teclado ----------------------------------------------------
    function setFocusDate(d) {
        focusDate = isoDate(d);
        var changedMonth = (d.getFullYear() !== viewYear) || (d.getMonth() + 1 !== viewMonth);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth() + 1;
        if (changedMonth && !Services.Config.reducedMotion) monthFade.restart();
    }

    function moveFocusByDays(delta) {
        var d = dateFromIso(focusDate);
        d.setDate(d.getDate() + delta);
        setFocusDate(d);
    }

    function moveFocusByMonths(delta) {
        var d = dateFromIso(focusDate);
        var day = d.getDate();
        d.setDate(1);
        d.setMonth(d.getMonth() + delta);
        var clampedDay = Math.min(day, daysInMonth(d.getFullYear(), d.getMonth() + 1));
        d.setDate(clampedDay);
        setFocusDate(d);
    }

    function selectFocusDate() {
        selectedDate = focusDate;
    }

    function selectCell(iso) {
        focusDate = iso;
        selectedDate = iso;
        var d = dateFromIso(iso);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth() + 1;
        root.forceActiveFocus();
    }

    Keys.onPressed: function (event) {
        switch (event.key) {
        case Qt.Key_Left: moveFocusByDays(-1); event.accepted = true; break;
        case Qt.Key_Right: moveFocusByDays(1); event.accepted = true; break;
        case Qt.Key_Up: moveFocusByDays(-7); event.accepted = true; break;
        case Qt.Key_Down: moveFocusByDays(7); event.accepted = true; break;
        case Qt.Key_PageUp: moveFocusByMonths(-1); event.accepted = true; break;
        case Qt.Key_PageDown: moveFocusByMonths(1); event.accepted = true; break;
        case Qt.Key_Home: goToday(); event.accepted = true; break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            selectFocusDate(); event.accepted = true; break;
        }
    }

    activeFocusOnTab: true

    // ============================================================================
    // UI
    // ============================================================================

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: root.spM

        // --- cabecera: mes/año + navegación ---------------------------------------
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: root.spS

            Text {
                id: monthLabel
                Layout.fillWidth: true
                text: root.monthNames[root.viewMonth - 1] + " " + root.viewYear
                color: Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E"
                font.pixelSize: root.fontL
                font.bold: true
                font.letterSpacing: 0.5
                elide: Text.ElideRight
            }

            Rectangle {
                id: todayBtn
                Layout.preferredWidth: Math.max(todayLabel.implicitWidth + root.spM * 2, root.minCellSize)
                Layout.preferredHeight: root.minCellSize
                radius: root.radiusChip
                color: todayArea.pressed
                    ? Qt.darker(Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F", 1.1)
                    : (Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F")

                Text {
                    id: todayLabel
                    anchors.centerIn: parent
                    text: "Hoy"
                    font.pixelSize: root.fontS
                    color: Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E"
                }

                MouseArea {
                    id: todayArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goToday()
                }
            }

            Rectangle {
                id: prevBtn
                Layout.preferredWidth: root.minCellSize
                Layout.preferredHeight: root.minCellSize
                radius: root.radiusChip
                color: prevArea.pressed
                    ? Qt.darker(Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F", 1.1)
                    : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "‹" // ‹
                    font.pixelSize: root.fontL
                    color: Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E"
                }

                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.changeViewMonth(-1)
                }
            }

            Rectangle {
                id: nextBtn
                Layout.preferredWidth: root.minCellSize
                Layout.preferredHeight: root.minCellSize
                radius: root.radiusChip
                color: nextArea.pressed
                    ? Qt.darker(Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F", 1.1)
                    : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "›" // ›
                    font.pixelSize: root.fontL
                    color: Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E"
                }

                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.changeViewMonth(1)
                }
            }
        }

        // --- fila de iniciales de los días (lunes primero) --------------------------
        RowLayout {
            id: weekRow
            Layout.fillWidth: true
            spacing: root.spXS

            Repeater {
                model: root.dayInitials
                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: root.fontXS
                    color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                }
            }
        }

        // --- rejilla de 6x7, opacidad animada al cambiar de mes (sin cambiar altura) -
        Item {
            id: gridHost
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: root.minCellSize * 6 + root.spXS * 5

            SequentialAnimation {
                id: monthFade
                NumberAnimation { target: gridHost; property: "opacity"; to: 0.35; duration: 90; easing.type: Easing.OutQuad }
                NumberAnimation { target: gridHost; property: "opacity"; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
            }

            GridLayout {
                id: grid
                anchors.fill: parent
                columns: 7
                rows: 6
                rowSpacing: root.spXS
                columnSpacing: root.spXS

                Repeater {
                    id: cellRepeater
                    model: root.cells

                    delegate: Item {
                        id: cellRoot
                        required property var modelData
                        required property int index

                        readonly property bool isToday: modelData.iso === root.todayIso
                        readonly property bool isSelected: modelData.iso === root.selectedDate
                        readonly property bool isFocused: root.activeFocus && modelData.iso === root.focusDate

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: root.minCellSize
                        Layout.minimumHeight: root.minCellSize

                        Rectangle {
                            id: cellBg
                            anchors.fill: parent
                            radius: root.radiusChip
                            color: cellRoot.isSelected
                                ? (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                                : (cellArea.pressed
                                    ? (Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F")
                                    : "transparent")
                        }

                        // anillo del "día de hoy": siempre visible en el borde,
                        // independiente de si además está seleccionado.
                        Rectangle {
                            anchors.fill: parent
                            radius: root.radiusChip
                            color: "transparent"
                            visible: cellRoot.isToday
                            border.width: 2
                            border.color: cellRoot.isSelected
                                ? (Services.Config.c ? Services.Config.c.onSurface : "#FFFFFF")
                                : (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                        }

                        // anillo de foco de teclado: distinto de "hoy" y de
                        // "seleccionado", visible solo cuando el widget tiene
                        // el foco de teclado.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -2
                            radius: root.radiusChip + 2
                            color: "transparent"
                            visible: cellRoot.isFocused
                            border.width: 2
                            border.color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: cellRoot.modelData.day
                                // "Cifras tabulares": la fuente del sistema puede no
                                // exponer la característica OpenType `tnum` (no es
                                // fiable entre versiones de Qt), así que forzamos el
                                // mismo efecto reservando un ancho fijo de 2
                                // caracteres para el número — ningún dígito puede
                                // desplazar el centrado de la celda al cambiar de mes.
                                width: 22
                                font.pixelSize: root.fontM
                                horizontalAlignment: Text.AlignHCenter
                                color: cellRoot.isSelected
                                    ? "#FFFFFF"
                                    : (cellRoot.modelData.inMonth
                                        ? (Services.Config.c ? Services.Config.c.onSurface : "#1C1C1E")
                                        : (Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"))
                                opacity: cellRoot.modelData.inMonth ? 1.0 : 0.45
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3
                                visible: cellRoot.modelData.hasEvents

                                Repeater {
                                    model: cellRoot.modelData.dots
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: modelData === "__neutral__"
                                            ? (Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73")
                                            : modelData
                                        opacity: cellRoot.isSelected ? 0.9 : 1.0
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectCell(cellRoot.modelData.iso)
                        }
                    }
                }
            }
        }
    }
}
