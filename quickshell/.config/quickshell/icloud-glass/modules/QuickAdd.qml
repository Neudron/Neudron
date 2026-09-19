// QuickAdd.qml — creación de recordatorios desde la GUI (propiedad exclusiva de B2).
//
// Botón "+" que despliega, de forma EMBEBIDA (no como ventana/Popup flotante:
// evita depender de QtQuick.Controls.Popup + Overlay, cuyo cierre no se puede
// vetar desde QML para el flujo de "confirmar descarte"), una tarjeta con el
// formulario de alta. La tarjeta ocupa su propio espacio en el layout vertical
// del widget que la aloja (empuja el contenido de abajo, no lo tapa).
//
// API pública de este archivo (uso desde RemindersWidget.qml):
//   property bool open            // true mientras la tarjeta está desplegada
//   function requestClose()       // intenta cerrar; si hay texto sin enviar,
//                                  // pide confirmación en vez de cerrar directo
//
// Llama a Services.Actions.newTodo(lista, resumen, dueIso) (API congelada,
// docs/CONTRACTS.md §6/§9). Actions es optimista, así que esta tarjeta NO
// cierra al enviar: espera actionSucceeded/actionFailed("newTodo", ...) para
// saber si de verdad fue bien, y si falla se queda abierta con lo escrito.

import QtQuick
import "../services" as Services

Item {
    id: root

    // --- escala fija del contrato (docs/CONTRACTS.md §4) ---
    readonly property int spXs: 4
    readonly property int spSm: 8
    readonly property int spMd: 12
    readonly property int spLg: 16
    readonly property int radiusChip: 12
    readonly property int radiusCard: 20
    readonly property int fontXs: 11
    readonly property int fontSm: 13
    readonly property int fontMd: 15

    // --- estado público ---
    property bool open: false

    // --- estado interno ---
    property string summaryText: ""
    property string selectedList: ""
    property string dueChoice: "none" // "none" | "today" | "tomorrow"
    property string errorText: ""
    property bool submitting: false
    property bool confirmingDiscard: false
    property bool justAdded: false

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    readonly property bool hasUnsavedText: root.summaryText.trim().length > 0

    function defaultListName() {
        var lists = Services.DataStore.lists || [];
        var wanted = (Services.Config.raw && Services.Config.raw.defaultList) || null;
        if (wanted) {
            for (var i = 0; i < lists.length; i++) {
                if (lists[i].name === wanted) return wanted;
            }
        }
        return lists.length > 0 ? lists[0].name : "";
    }

    function listExists(name) {
        var lists = Services.DataStore.lists || [];
        for (var i = 0; i < lists.length; i++) {
            if (lists[i].name === name) return true;
        }
        return false;
    }

    function openPopover() {
        if (!root.selectedList || !root.listExists(root.selectedList))
            root.selectedList = root.defaultListName();
        root.errorText = "";
        root.confirmingDiscard = false;
        root.open = true;
        Qt.callLater(function () { summaryInput.forceActiveFocus(); });
    }

    // Cierre "educado": si hay texto sin enviar pide confirmación en vez de
    // cerrar de golpe (requisito explícito de UX del contrato de la tarea).
    function requestClose() {
        if (!root.open) return;
        if (root.hasUnsavedText && !root.confirmingDiscard) {
            root.confirmingDiscard = true;
            return;
        }
        forceClose();
    }

    function forceClose() {
        root.open = false;
        root.confirmingDiscard = false;
        root.errorText = "";
    }

    function computeDueIso() {
        if (root.dueChoice === "none") return null;
        var d = new Date();
        if (root.dueChoice === "tomorrow") {
            d.setDate(d.getDate() + 1);
            d.setHours(9, 0, 0, 0);
        } else {
            d.setHours(23, 59, 0, 0);
        }
        return d.toISOString();
    }

    function submit() {
        var summary = root.summaryText.trim();
        if (summary.length === 0) {
            root.errorText = "Escribe un texto para el recordatorio.";
            return;
        }
        if (!root.selectedList) {
            root.errorText = "Elige una lista de destino.";
            return;
        }
        root.errorText = "";
        root.submitting = true;
        Services.Actions.newTodo(root.selectedList, summary, root.computeDueIso());
    }

    Connections {
        target: Services.Actions
        function onActionSucceeded(what) {
            if (what !== "newTodo" || !root.submitting) return;
            root.submitting = false;
            root.summaryText = "";
            root.dueChoice = "none";
            root.errorText = "";
            root.open = false;
            root.confirmingDiscard = false;
            root.justAdded = true;
            justAddedTimer.restart();
        }
        function onActionFailed(what, message) {
            if (what !== "newTodo" || !root.submitting) return;
            root.submitting = false;
            root.errorText = message;
        }
    }

    Timer {
        id: justAddedTimer
        interval: 1600
        onTriggered: root.justAdded = false
    }

    Keys.onEscapePressed: root.requestClose()

    Column {
        id: column
        width: root.parent ? root.parent.width : implicitWidth
        spacing: root.spSm

        // --- fila del botón "+" ---
        Item {
            width: parent.width
            height: Math.max(addButton.height, 24)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                visible: root.justAdded
                text: "Recordatorio añadido"
                color: Services.Config.c ? Services.Config.c.success : "#30D158"
                font.pixelSize: root.fontSm
            }

            Rectangle {
                id: addButton
                anchors.right: parent.right
                width: 44
                height: 44
                radius: root.radiusChip
                color: addArea.pressed
                    ? Qt.darker(Services.Config.c ? Services.Config.c.accent : "#0A84FF", 1.15)
                    : (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                activeFocusOnTab: true

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "#FFFFFF"
                    font.pixelSize: 22
                    font.bold: true
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: Services.Config.c ? Services.Config.c.accent : "#0A84FF"
                    visible: addButton.activeFocus
                    opacity: 0.9
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open ? root.requestClose() : root.openPopover()
                }
                Keys.onReturnPressed: root.open ? root.requestClose() : root.openPopover()
                Keys.onSpacePressed: root.open ? root.requestClose() : root.openPopover()

                Accessible.name: "Nuevo recordatorio"
                Accessible.role: Accessible.Button
            }
        }

        // --- tarjeta desplegable ---
        Loader {
            width: parent.width
            active: root.open
            sourceComponent: cardComponent
        }
    }

    Component {
        id: cardComponent

        Rectangle {
            id: card
            width: parent ? parent.width : 0
            implicitHeight: cardColumn.implicitHeight + root.spLg * 2
            height: implicitHeight
            radius: root.radiusCard
            color: Services.Config.c ? Services.Config.c.surfaceRaised : "#1A1A1F"
            border.width: 1
            border.color: Services.Config.c
                ? Qt.rgba(Services.Config.c.stroke.r, Services.Config.c.stroke.g, Services.Config.c.stroke.b, Services.Config.c.strokeAlpha)
                : "#00000000"

            MouseArea {
                // Absorbe los clics dentro de la tarjeta para que no lleguen
                // al detector de "clic fuera" de RemindersWidget.
                anchors.fill: parent
                onClicked: (mouse) => { mouse.accepted = true; }
                preventStealing: false
                propagateComposedEvents: false
            }

            Column {
                id: cardColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.spLg
                spacing: root.spMd

                // --- confirmación de descarte ---
                Column {
                    width: parent.width
                    spacing: root.spSm
                    visible: root.confirmingDiscard

                    Text {
                        width: parent.width
                        text: "¿Descartar el recordatorio sin guardar?"
                        color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                        font.pixelSize: root.fontMd
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: root.spSm
                        Rectangle {
                            width: Math.max(cancelDiscardLabel.implicitWidth + 24, 44)
                            height: 36
                            radius: root.radiusChip
                            color: "transparent"
                            border.width: 1
                            border.color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                            activeFocusOnTab: true
                            Text {
                                id: cancelDiscardLabel
                                anchors.centerIn: parent
                                text: "Seguir editando"
                                color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                                font.pixelSize: root.fontSm
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.confirmingDiscard = false }
                            Keys.onReturnPressed: root.confirmingDiscard = false
                        }
                        Rectangle {
                            width: Math.max(discardLabel.implicitWidth + 24, 44)
                            height: 36
                            radius: root.radiusChip
                            color: Services.Config.c ? Services.Config.c.danger : "#FF453A"
                            activeFocusOnTab: true
                            Text {
                                id: discardLabel
                                anchors.centerIn: parent
                                text: "Descartar"
                                color: "#FFFFFF"
                                font.pixelSize: root.fontSm
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.forceClose() }
                            Keys.onReturnPressed: root.forceClose()
                        }
                    }
                }

                // --- formulario ---
                Column {
                    width: parent.width
                    spacing: root.spMd
                    visible: !root.confirmingDiscard

                    // texto del recordatorio
                    Column {
                        width: parent.width
                        spacing: root.spXs
                        Text {
                            text: "Recordatorio"
                            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                            font.pixelSize: root.fontXs
                        }
                        Rectangle {
                            width: parent.width
                            height: 40
                            radius: root.radiusChip
                            color: Services.Config.c ? Services.Config.c.surface : "#0E0E11"
                            border.width: summaryInput.activeFocus ? 2 : 1
                            border.color: summaryInput.activeFocus
                                ? (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                                : (Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73")

                            TextInput {
                                id: summaryInput
                                anchors.fill: parent
                                anchors.leftMargin: root.spSm
                                anchors.rightMargin: root.spSm
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                                font.pixelSize: root.fontMd
                                text: root.summaryText
                                activeFocusOnTab: true
                                onTextChanged: root.summaryText = text
                                Keys.onReturnPressed: root.submit()
                            }
                        }
                    }

                    // selector de lista
                    Column {
                        width: parent.width
                        spacing: root.spXs
                        Text {
                            text: "Lista"
                            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                            font.pixelSize: root.fontXs
                        }
                        Flow {
                            width: parent.width
                            spacing: root.spSm
                            Repeater {
                                model: Services.DataStore.lists
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: root.selectedList === modelData.name
                                    height: 32
                                    width: listChipLabel.implicitWidth + root.spMd * 2
                                    radius: root.radiusChip
                                    color: selected
                                        ? (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                                        : "transparent"
                                    border.width: 1
                                    border.color: modelData.color
                                    activeFocusOnTab: true

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: root.spXs
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: modelData.color
                                        }
                                        Text {
                                            id: listChipLabel
                                            text: modelData.name
                                            color: selected ? "#FFFFFF" : (Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7")
                                            font.pixelSize: root.fontSm
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.selectedList = modelData.name }
                                    Keys.onReturnPressed: root.selectedList = modelData.name
                                }
                            }
                        }
                    }

                    // vencimiento
                    Column {
                        width: parent.width
                        spacing: root.spXs
                        Text {
                            text: "Vencimiento"
                            color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#A1A1AA"
                            font.pixelSize: root.fontXs
                        }
                        Row {
                            spacing: root.spSm
                            Repeater {
                                model: [
                                    { key: "today", label: "Hoy" },
                                    { key: "tomorrow", label: "Mañana" },
                                    { key: "none", label: "Sin fecha" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: root.dueChoice === modelData.key
                                    height: 32
                                    width: dueChipLabel.implicitWidth + root.spMd * 2
                                    radius: root.radiusChip
                                    color: selected
                                        ? (Services.Config.c ? Services.Config.c.accent : "#0A84FF")
                                        : "transparent"
                                    border.width: 1
                                    border.color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                                    activeFocusOnTab: true

                                    Text {
                                        id: dueChipLabel
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: selected ? "#FFFFFF" : (Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7")
                                        font.pixelSize: root.fontSm
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.dueChoice = modelData.key }
                                    Keys.onReturnPressed: root.dueChoice = modelData.key
                                }
                            }
                        }
                    }

                    // error, DEBAJO del campo (requisito de UX)
                    Text {
                        width: parent.width
                        visible: root.errorText.length > 0
                        text: root.errorText
                        color: Services.Config.c ? Services.Config.c.danger : "#FF453A"
                        font.pixelSize: root.fontSm
                        wrapMode: Text.WordWrap
                    }

                    // acciones
                    Row {
                        spacing: root.spSm
                        Rectangle {
                            width: Math.max(cancelLabel.implicitWidth + 24, 44)
                            height: 36
                            radius: root.radiusChip
                            color: "transparent"
                            border.width: 1
                            border.color: Services.Config.c ? Services.Config.c.onSurfaceMuted : "#6E6E73"
                            activeFocusOnTab: true
                            Text {
                                id: cancelLabel
                                anchors.centerIn: parent
                                text: "Cancelar"
                                color: Services.Config.c ? Services.Config.c.onSurface : "#F5F5F7"
                                font.pixelSize: root.fontSm
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.requestClose() }
                            Keys.onReturnPressed: root.requestClose()
                        }
                        Rectangle {
                            id: submitButton
                            width: Math.max(submitLabel.implicitWidth + 24, 44)
                            height: 36
                            radius: root.radiusChip
                            opacity: Services.Actions.busy ? 0.6 : 1.0
                            color: Services.Config.c ? Services.Config.c.accent : "#0A84FF"
                            activeFocusOnTab: true

                            Text {
                                id: submitLabel
                                anchors.centerIn: parent
                                text: Services.Actions.busy ? "Añadiendo…" : "Añadir"
                                color: "#FFFFFF"
                                font.pixelSize: root.fontSm
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !Services.Actions.busy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.submit()
                            }
                            Keys.onReturnPressed: if (!Services.Actions.busy) root.submit()
                        }
                    }
                }
            }
        }
    }
}
