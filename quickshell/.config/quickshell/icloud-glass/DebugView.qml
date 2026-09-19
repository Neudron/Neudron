// DebugView.qml — vista mínima de texto plano para comprobar que Config,
// DataStore y Actions cargan y exponen datos correctos, sin depender de que
// el panel "bonito" (components/, modules/) esté montado.
//
// Prueba manual, con las fixtures del repo (contienen los casos duros:
// evento recurrente, evento multi-día con DST, todo vencido, etc.):
//
//   ICLOUD_GLASS_CACHE_DIR=$PWD/tests/fixtures qs -p quickshell/.config/quickshell/icloud-glass/DebugView.qml
//
// También puede lanzarse sin fixtures para ver el comportamiento con la
// caché real del usuario (o vacía, si icloud-glass-sync no ha corrido aún):
//
//   qs -p quickshell/.config/quickshell/icloud-glass/DebugView.qml
//
// Nota: NO se pudo ejecutar `qs` en este entorno (Quickshell no está
// instalado en el contenedor de verificación); esta vista se revisó a mano.
import QtQuick
import QtQuick.Window
import "./services" as Services

Window {
    id: win
    width: 640
    height: 800
    visible: true
    color: "#101014"
    title: "icloud-glass · DebugView"

    Flickable {
        anchors.fill: parent
        anchors.margins: 12
        contentHeight: dump.implicitHeight
        clip: true

        Text {
            id: dump
            width: win.width - 24
            wrapMode: Text.Wrap
            color: "#EEEEEE"
            font.family: "monospace"
            font.pixelSize: 13
            text: win.buildDump()
        }
    }

    // Refresca el volcado cuando cambia cualquier dato relevante.
    Connections {
        target: Services.DataStore
        function onEventsChanged() { dump.text = win.buildDump(); }
        function onTodosChanged() { dump.text = win.buildDump(); }
        function onStatusChanged() { dump.text = win.buildDump(); }
        function onReadyChanged() { dump.text = win.buildDump(); }
    }
    Connections {
        target: Services.Config
        function onReloaded() { dump.text = win.buildDump(); }
    }

    function isoToday() {
        var d = new Date();
        var y = d.getFullYear();
        var m = ("0" + (d.getMonth() + 1)).slice(-2);
        var dd = ("0" + d.getDate()).slice(-2);
        return y + "-" + m + "-" + dd;
    }

    function fmtEvent(e) {
        var when = e.allDay ? "[todo el día]" : (e.start || "?");
        var span = (e.startDate !== e.endDate) ? (" (" + e.startDate + " -> " + e.endDate + ")") : "";
        return "  - " + when + span + "  " + e.title + "  [" + e.calendar + "]" +
               (e.cancelled ? "  CANCELADO" : "");
    }

    function fmtTodo(t) {
        var box = t.completed ? "[x]" : "[ ]";
        var due = t.due ? (" due:" + t.due) : "";
        var over = t.overdue ? " VENCIDO" : "";
        return "  " + box + " " + t.summary + due + over + "  (" + t.priorityLabel + ")";
    }

    function buildDump() {
        var ds = Services.DataStore;
        var cfg = Services.Config;
        var out = [];

        out.push("=== icloud-glass · DebugView ===");
        out.push("");
        out.push("-- Config --");
        out.push("theme configurado: " + cfg.raw.theme + "  ->  dark=" + cfg.dark);
        out.push("reducedMotion: " + cfg.reducedMotion);
        out.push("hiddenCalendars: " + JSON.stringify(cfg.raw.hiddenCalendars));
        out.push("hiddenLists: " + JSON.stringify(cfg.raw.hiddenLists));
        out.push("");

        out.push("-- Estado (DataStore.ready / status) --");
        out.push("ready: " + ds.ready);
        out.push("status.state: " + (ds.status ? ds.status.state : "?"));
        out.push("status.error: " + (ds.status ? ds.status.error : "?"));
        out.push("status.lastSync: " + (ds.status ? ds.status.lastSync : "?"));
        out.push("");

        out.push("-- Contadores --");
        out.push("eventos totales (filtrados): " + ds.events.length);
        out.push("todos totales (filtrados): " + ds.todos.length);
        out.push("calendarios: " + ds.calendars.length + "  listas: " + ds.lists.length);
        out.push("");

        out.push("-- Próximos 5 eventos (upcoming) --");
        var up = ds.upcoming(5);
        if (up.length === 0) out.push("  (ninguno)");
        for (var i = 0; i < up.length; i++) out.push(fmtEvent(up[i]));
        out.push("");

        var today = win.isoToday();
        out.push("-- Eventos de hoy (" + today + ") --");
        var todays = ds.eventsOn(today);
        if (todays.length === 0) out.push("  (ninguno)");
        for (var j = 0; j < todays.length; j++) out.push(fmtEvent(todays[j]));
        out.push("colores de hoy: " + JSON.stringify(ds.colorsOn(today)));
        out.push("hasEventsOn(hoy): " + ds.hasEventsOn(today));
        out.push("");

        out.push("-- Todos agrupados por lista --");
        for (var k = 0; k < ds.lists.length; k++) {
            var list = ds.lists[k];
            out.push(list.name + "  (pending=" + list.pending + " completed=" + list.completed + ")");
            var items = ds.todosFor(list.name);
            if (items.length === 0) out.push("  (vacía)");
            for (var m = 0; m < items.length; m++) out.push(fmtTodo(items[m]));
        }

        return out.join("\n");
    }
}
