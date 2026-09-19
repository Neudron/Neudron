// RemindersWidget.qml — recordatorios de iCloud, agrupados por lista
// (propiedad exclusiva de B2). Consume exclusivamente la API congelada de
// Services.DataStore / Services.Actions / Services.Config (docs/CONTRACTS.md
// §6) y los componentes compartidos GlassSurface/States (§5, components/).
//
// No mantiene su propio estado de "completado": el check llama a
// Actions.completeTodo(uid, !completed) y confía en que Actions/DataStore ya
// son optimistas (aplican el cambio y revierten solos si falla). Este
// archivo solo anima la transición visual y muestra el aviso si falla.

import QtQuick
import QtQuick.Layouts
import "../services" as Services
import "../components" as Components

Item {
    id: root

    // --- escala fija del contrato (docs/CONTRACTS.md §4) ---
    readonly property int spXs: 4
    readonly property int spSm: 8
    readonly property int spMd: 12
    readonly property int spLg: 16
    readonly property int spXl: 24
    readonly property int radiusChip: 12
    readonly property int radiusCard: 20
    readonly property int fontXs: 11
    readonly property int fontSm: 13
    readonly property int fontMd: 15
    readonly property int fontLg: 17

    readonly property int transitionMs: Services.Config.reducedMotion ? 0 : 200

    implicitWidth: 360
    implicitHeight: 480

    // Recuerda, mientras viva el panel, qué secciones "Completados" de cada
    // lista están desplegadas. Arrancan todas cerradas (objeto vacío).
    property var completedExpanded: ({})

    function isCompletedExpanded(listName) {
        return !!root.completedExpanded[listName];
    }

    function toggleCompleted(listName) {
        var next = {};
        for (var k in root.completedExpanded) next[k] = root.completedExpanded[k];
        next[listName] = !next[listName];
        root.completedExpanded = next;
    }

    // --- modelo plano para la ListView virtualizada -----------------------
    // Cada elemento: {type: "header"|"empty"|"completedHeader"|"todo", ...}
    readonly property var flatItems: buildFlatItems()
    readonly property int totalTodoCount: sumTodoCount()

    function sumTodoCount() {
        var lists = Services.DataStore.lists || [];
        var total = 0;
        for (var i = 0; i < lists.length; i++)
            total += (lists[i].pending || 0) + (lists[i].completed || 0);
        return total;
    }

    function buildFlatItems() {
        var items = [];
        var lists = Services.DataStore.lists || [];
        for (var i = 0; i < lists.length; i++) {
            var list = lists[i];
            var listTodos = Services.DataStore.todosFor(list.name);
            var pending = [];
            var completed = [];
            for (var j = 0; j < listTodos.length; j++) {
                if (listTodos[j].completed) completed.push(listTodos[j]);
                else pending.push(listTodos[j]);
            }

            items.push({
                type: "header",
                list: list.name,
                color: list.color,
                pendingCount: pending.length
            });

            if (pending.length === 0) {
                items.push({ type: "empty", list: list.name });
            } else {
                for (var p = 0; p < pending.length; p++)
                    items.push({ type: "todo", todo: pending[p] });
            }

            if (completed.length > 0) {
                var expanded = root.isCompletedExpanded(list.name);
                items.push({
                    type: "completedHeader",
                    list: list.name,
                    count: completed.length,
                    expanded: expanded
                });
                if (expanded) {
                    for (var c = 0; c < completed.length; c++)
                        items.push({ type: "todo", todo: completed[c] });
                }
            }
        }
        return items;
    }

    // --- fecha/hora relativas en español -----------------------------------
    // Se recalculan solas al cruzar la medianoche mediante un único timer
    // reprogramado (nunca un timer de 1s/polling), ver `nowTick` más abajo.
    property int nowTick: 0

    readonly property var monthNames: ["ene", "feb", "mar", "abr", "may", "jun",
        "jul", "ago", "sep", "oct", "nov", "dic"]
    readonly property var weekdayNames: ["domingo", "lunes", "martes", "miércoles",
        "jueves", "viernes", "sábado"]

    function isoDate(d) {
        var y = d.getFullYear();
        var m = ("0" + (d.getMonth() + 1)).slice(-2);
        var dd = ("0" + d.getDate()).slice(-2);
        return y + "-" + m + "-" + dd;
    }

    function daysDiff(dateStr, todayStr) {
        var a = dateStr.split("-").map(function (n) { return parseInt(n, 10); });
        var b = todayStr.split("-").map(function (n) { return parseInt(n, 10); });
        var msA = Date.UTC(a[0], a[1] - 1, a[2]);
        var msB = Date.UTC(b[0], b[1] - 1, b[2]);
        return Math.round((msA - msB) / 86400000);
    }

    function formatTime(iso) {
        var m = /T(\d{2}):(\d{2})/.exec(iso);
        return m ? (m[1] + ":" + m[2]) : "";
    }

    function absoluteDate(dateStr, todayStr) {
        var parts = dateStr.split("-").map(function (n) { return parseInt(n, 10); });
        var todayParts = todayStr.split("-").map(function (n) { return parseInt(n, 10); });
        var day = parts[2];
        var month = root.monthNames[parts[1] - 1];
        if (parts[0] !== todayParts[0])
            return day + " " + month + " " + parts[0];
        return day + " " + month;
    }

    // Texto relativo/absoluto de vencimiento, en español. `todo` viene del
    // contrato (todos.json §2): due, dueDate, dueAllDay, overdue.
    function formatDue(todo) {
        root.nowTick; // dependencia intencional (reevaluar al cambiar el día)
        if (!todo.dueDate) return "";
        var now = new Date();
        var todayStr = root.isoDate(now);
        var diff = root.daysDiff(todo.dueDate, todayStr);
        var timePart = todo.dueAllDay ? "" : root.formatTime(todo.due);

        if (todo.overdue) {
            if (diff === 0) return "Vencido hoy" + (timePart ? " " + timePart : "");
            if (diff === -1) return "Vencido ayer" + (timePart ? " " + timePart : "");
            return "Vencido hace " + Math.abs(diff) + " días";
        }

        if (diff === 0) return timePart ? ("Hoy " + timePart) : "Hoy";
        if (diff === 1) return timePart ? ("Mañana " + timePart) : "Mañana";
        if (diff === -1) return "Ayer" + (timePart ? " " + timePart : "");
        if (diff > 1 && diff <= 6) {
            var d = new Date(todo.dueDate + "T00:00:00");
            var label = "el " + root.weekdayNames[d.getDay()];
            return timePart ? (label + " " + timePart) : label;
        }
        var abs = root.absoluteDate(todo.dueDate, todayStr);
        return timePart ? (abs + " " + timePart) : abs;
    }

    function priorityText(label) {
        switch (label) {
        case "high": return "Prioridad alta";
        case "medium": return "Prioridad media";
        case "low": return "Prioridad baja";
        default: return "";
        }
    }

    // Reprograma un único disparo para justo después de la medianoche
    // siguiente (nunca un timer de segundo en segundo).
    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: {
            root.nowTick = root.nowTick + 1;
            root.scheduleMidnightTick();
        }
    }

    function scheduleMidnightTick() {
        var now = new Date();
        var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5, 0);
        var ms = Math.max(1000, next.getTime() - now.getTime());
        midnightTimer.interval = ms;
        midnightTimer.start();
    }

    Component.onCompleted: scheduleMidnightTick()

    // --- aviso breve y no intrusivo si falla completar/reabrir -------------
    property string toastText: ""
    property bool toastVisible: false

    Connections {
        target: Services.Actions
        function onActionFailed(what, message) {
            if (what !== "completeTodo") return;
            root.toastText = message + " Se ha revertido.";
            root.toastVisible = true;
            toastTimer.restart();
        }
    }

    Timer {
        id: toastTimer
        interval: 4000
        onTriggered: root.toastVisible = false
    }

    Components.GlassSurface {
        id: surface
        anchors.fill: parent
        radius: root.radiusCard

        Item {
            anchors.fill: parent

            ColumnLayout {
                id: mainColumn
                anchors.fill: parent
                anchors.margins: root.spLg
                spacing: root.spMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.spSm

                    Text {
                        Layout.fillWidth: true
                        text: "Recordatorios"
                        color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                        font.pixelSize: root.fontLg
                        font.bold: true
                    }
                }

                QuickAdd {
                    id: quickAdd
                    Layout.fillWidth: true
                    z: 10
                }

                Item {
                    id: restArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Components.States {
                        id: states
                        anchors.fill: parent
                        kind: root.totalTodoCount === 0 ? Components.States.Empty : Components.States.None
                        emptyMessage: "No hay recordatorios"

                        ListView {
                            id: listView
                            anchors.fill: parent
                            clip: true
                            focus: true
                            spacing: root.spXs
                            model: root.flatItems
                            cacheBuffer: 400

                            Keys.onPressed: (event) => {
                                if (event.key !== Qt.Key_Space) return;
                                var it = root.flatItems[listView.currentIndex];
                                if (!it) return;
                                if (it.type === "todo") {
                                    Services.Actions.completeTodo(it.todo.uid, !it.todo.completed);
                                    event.accepted = true;
                                } else if (it.type === "completedHeader") {
                                    root.toggleCompleted(it.list);
                                    event.accepted = true;
                                }
                            }

                            delegate: Item {
                                id: delegateRoot
                                required property var modelData
                                required property int index
                                width: listView.width
                                height: loader.item ? loader.item.implicitHeight : 0

                                readonly property bool isCurrent: ListView.isCurrentItem

                                Loader {
                                    id: loader
                                    width: parent.width
                                    sourceComponent: {
                                        switch (delegateRoot.modelData.type) {
                                        case "header": return headerComponent;
                                        case "empty": return emptyComponent;
                                        case "completedHeader": return completedHeaderComponent;
                                        default: return todoComponent;
                                        }
                                    }
                                    onLoaded: {
                                        if (item) item.itemData = delegateRoot.modelData;
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    visible: delegateRoot.isCurrent
                                    color: "transparent"
                                    radius: root.spSm
                                    border.width: 2
                                    border.color: Services.Config.c ? Services.Config.c.accent : "#0A84FF"
                                }

                                // --- cabecera de lista ---
                                Component {
                                    id: headerComponent
                                    Item {
                                        id: headerRoot
                                        property var itemData
                                        implicitHeight: headerRow.implicitHeight + root.spMd

                                        RowLayout {
                                            id: headerRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: root.spSm
                                            spacing: root.spSm

                                            Rectangle {
                                                width: 10; height: 10; radius: 5
                                                color: headerRoot.itemData ? headerRoot.itemData.color : "#888888"
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: headerRoot.itemData ? headerRoot.itemData.list : ""
                                                color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                                                font.pixelSize: root.fontMd
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: headerRoot.itemData ? headerRoot.itemData.pendingCount : 0
                                                color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                                                font.pixelSize: root.fontSm
                                            }
                                        }
                                    }
                                }

                                // --- "todo hecho" por lista ---
                                Component {
                                    id: emptyComponent
                                    Item {
                                        property var itemData
                                        implicitHeight: emptyText.implicitHeight + root.spSm

                                        Text {
                                            id: emptyText
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            text: "Todo hecho"
                                            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                                            font.pixelSize: root.fontSm
                                            font.italic: true
                                        }
                                    }
                                }

                                // --- cabecera "Completados (N)" colapsable ---
                                Component {
                                    id: completedHeaderComponent
                                    Item {
                                        id: completedHeaderRoot
                                        property var itemData
                                        implicitHeight: 44

                                        Accessible.role: Accessible.Button
                                        Accessible.name: completedHeaderRoot.itemData
                                            ? ("Completados (" + completedHeaderRoot.itemData.count + ")")
                                            : "Completados"

                                        Row {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: root.spXs

                                            Text {
                                                text: completedHeaderRoot.itemData && completedHeaderRoot.itemData.expanded ? "▾" : "▸"
                                                color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                                                font.pixelSize: root.fontSm
                                            }
                                            Text {
                                                text: completedHeaderRoot.itemData
                                                    ? ("Completados (" + completedHeaderRoot.itemData.count + ")")
                                                    : "Completados"
                                                color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                                                font.pixelSize: root.fontSm
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.toggleCompleted(completedHeaderRoot.itemData.list)
                                        }
                                    }
                                }

                                // --- fila de recordatorio ---
                                Component {
                                    id: todoComponent
                                    Item {
                                        id: todoRoot
                                        property var itemData
                                        readonly property var todo: itemData ? itemData.todo : null
                                        implicitHeight: 44

                                        Row {
                                            anchors.fill: parent
                                            spacing: root.spSm

                                            // círculo de check, área táctil >= 44px
                                            Item {
                                                width: 44
                                                height: 44
                                                anchors.verticalCenter: parent.verticalCenter

                                                Rectangle {
                                                    id: checkCircle
                                                    anchors.centerIn: parent
                                                    width: 22
                                                    height: 22
                                                    radius: 11
                                                    color: "transparent"
                                                    border.width: 2
                                                    border.color: todoRoot.todo && todoRoot.todo.overdue && !todoRoot.todo.completed
                                                        ? (Services.Config.c ? Services.Config.c.danger : "#FF453A")
                                                        : (todoRoot.todo && todoRoot.todo.color ? todoRoot.todo.color : (Services.Config.c ? Services.Config.c.accent : "#0A84FF"))

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: parent.radius
                                                        color: todoRoot.todo && todoRoot.todo.color ? todoRoot.todo.color : (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                                                        opacity: todoRoot.todo && todoRoot.todo.completed ? 1.0 : 0.0
                                                        Behavior on opacity { NumberAnimation { duration: root.transitionMs } }
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✓"
                                                        color: "#FFFFFF"
                                                        font.pixelSize: 13
                                                        opacity: todoRoot.todo && todoRoot.todo.completed ? 1.0 : 0.0
                                                        Behavior on opacity { NumberAnimation { duration: root.transitionMs } }
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        listView.currentIndex = delegateRoot.index;
                                                        if (todoRoot.todo)
                                                            Services.Actions.completeTodo(todoRoot.todo.uid, !todoRoot.todo.completed);
                                                    }
                                                }

                                                Accessible.role: Accessible.CheckBox
                                                Accessible.checked: !!(todoRoot.todo && todoRoot.todo.completed)
                                                Accessible.name: todoRoot.todo ? todoRoot.todo.summary : ""
                                            }

                                            Column {
                                                width: parent.width - 44 - root.spSm
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 2

                                                Text {
                                                    width: parent.width
                                                    text: todoRoot.todo ? todoRoot.todo.summary : ""
                                                    color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                                                    font.pixelSize: root.fontMd
                                                    font.strikeout: !!(todoRoot.todo && todoRoot.todo.completed)
                                                    opacity: todoRoot.todo && todoRoot.todo.completed ? 0.55 : 1.0
                                                    elide: Text.ElideRight
                                                    Behavior on opacity { NumberAnimation { duration: root.transitionMs } }
                                                }

                                                Row {
                                                    spacing: root.spSm
                                                    visible: (todoRoot.todo && (todoRoot.todo.dueDate || todoRoot.todo.priorityLabel !== "none"))

                                                    Text {
                                                        visible: !!(todoRoot.todo && todoRoot.todo.dueDate)
                                                        text: todoRoot.todo ? root.formatDue(todoRoot.todo) : ""
                                                        color: todoRoot.todo && todoRoot.todo.overdue && !todoRoot.todo.completed
                                                            ? (Services.Config.c ? Services.Config.c.danger : "#FF453A")
                                                            : (Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA")
                                                        font.pixelSize: root.fontXs
                                                        font.bold: !!(todoRoot.todo && todoRoot.todo.overdue && !todoRoot.todo.completed)
                                                    }
                                                    Text {
                                                        visible: !!(todoRoot.todo && todoRoot.todo.priorityLabel && todoRoot.todo.priorityLabel !== "none")
                                                        text: todoRoot.todo ? root.priorityText(todoRoot.todo.priorityLabel) : ""
                                                        color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                                                        font.pixelSize: root.fontXs
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- detector de "clic fuera" para cerrar QuickAdd ---
                    MouseArea {
                        anchors.fill: parent
                        z: 1000
                        visible: quickAdd.open
                        enabled: quickAdd.open
                        onPressed: quickAdd.requestClose()
                    }
                }
            }

            // --- aviso breve tras un fallo al completar/reabrir ---
            Rectangle {
                id: toast
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.spLg
                z: 2000
                visible: opacity > 0
                opacity: root.toastVisible ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: root.transitionMs } }

                width: Math.min(toastLabel.implicitWidth + root.spLg * 2, parent.width - root.spLg * 2)
                height: toastLabel.implicitHeight + root.spMd
                radius: root.radiusChip
                color: Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F"
                border.width: 1
                border.color: Services.Config.c ? Services.Config.c.danger : "#FF453A"

                Text {
                    id: toastLabel
                    anchors.centerIn: parent
                    width: parent.width - root.spMd
                    text: root.toastText
                    color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                    font.pixelSize: root.fontSm
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
