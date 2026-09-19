pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// DataStore: lee events.json, todos.json y status.json desde el directorio de
// caché (ICLOUD_GLASS_CACHE_DIR, o XDG_CACHE_HOME/icloud-glass, o
// ~/.cache/icloud-glass) mediante FileView + watchChanges (inotify, sin
// polling), y expone modelos ya filtrados/normalizados a los widgets.
//
// API pública (congelada, ver docs/CONTRACTS.md §6):
//   events, todos, calendars, lists, status, ready,
//   eventsOn(dateString), upcoming(n), hasEventsOn(dateString),
//   colorsOn(dateString), todosFor(listName)
//
// Además expone unas funciones internas con prefijo `_` que NO son parte del
// contrato congelado: son el canal privado que usa Actions.qml (también mío)
// para aplicar cambios optimistas. Ningún otro agente debería depender de
// ellas.
Singleton {
    id: root

    // ---------------------------------------------------------------
    // Quickshell 0.3.1 issue #1082: JsonAdapter/FileView puede provocar un
    // SIGSEGV durante el teardown si la instancia se destruye mientras hay
    // una recarga en curso (por ejemplo, al recargar la config del shell).
    // Mitigación: los FileView viven dentro de un Loader cuya propiedad
    // `active` controlamos nosotros, en vez de crearlos directamente como
    // hijos permanentes del singleton. Así el ciclo de vida es explícito y,
    // si algún día hace falta recrearlos, se hace desactivando/activando el
    // Loader en un orden controlado en vez de dejar que Quickshell destruya
    // y reconstruya el singleton completo.
    // ---------------------------------------------------------------

    readonly property string cacheDir: {
        var override = Quickshell.env("ICLOUD_GLASS_CACHE_DIR");
        if (override && override.length > 0) return override;
        var xdgCache = Quickshell.env("XDG_CACHE_HOME");
        var base = (xdgCache && xdgCache.length > 0) ? xdgCache
                   : (Quickshell.env("HOME") + "/.cache");
        return base + "/icloud-glass";
    }

    // --- Datos crudos (tal cual el último JSON válido parseado) ---
    property var rawEvents: []
    property var rawCalendars: []
    property var rawTodos: []
    property var rawLists: []
    property var rawStatus: ({
        schema: 1, state: "error", lastSync: null, lastSyncOk: null,
        durationMs: null, error: null, errorKind: null,
        counts: { events: 0, todos: 0, calendars: 0, lists: 0 }
    })

    property bool eventsLoadedOnce: false
    property bool todosLoadedOnce: false
    property bool statusLoadedOnce: false

    // Entradas "fantasma" optimistas añadidas por Actions.qml a la espera de
    // que icloud-glass-refresh escriba la versión real en disco.
    property var pendingNewTodos: []
    property var pendingNewEvents: []
    // Overrides por uid (p.ej. completeTodo) aplicados sobre rawTodos.
    property var todoOverrides: ({})

    // --- API pública ---

    readonly property var events: expandAndFilterEvents()
    readonly property var todos: filterTodos(mergeTodoOverrides(rawTodos).concat(pendingNewTodos))
    readonly property var calendars: rawCalendars
    readonly property var lists: rawLists
    readonly property var status: rawStatus
    readonly property bool ready: eventsLoadedOnce && todosLoadedOnce

    function eventsOn(dateString) {
        return dayCacheEntry(dateString).events;
    }

    function hasEventsOn(dateString) {
        return dayCacheEntry(dateString).events.length > 0;
    }

    function colorsOn(dateString) {
        return dayCacheEntry(dateString).colors;
    }

    function upcoming(n) {
        var now = new Date();
        var nowMs = now.getTime();
        var todayStr = isoDate(now);
        var list = events.filter(function (e) {
            if (e.allDay) {
                // Incluye los all-day de hoy y los futuros; descarta los que
                // ya han terminado (endDate anterior a hoy).
                return e.endDate >= todayStr;
            }
            if (!e.end) return true;
            var endMs = Date.parse(e.end);
            if (isNaN(endMs)) return true;
            return endMs >= nowMs;
        });
        list.sort(compareUpcoming);
        return list.slice(0, n);
    }

    function todosFor(listName) {
        return todos.filter(function (t) { return t.list === listName; });
    }

    // --- Funciones internas para Actions.qml (no forman parte del contrato) ---

    function _findTodo(uid) {
        for (var i = 0; i < rawTodos.length; i++) {
            if (rawTodos[i].uid === uid) return rawTodos[i];
        }
        for (var j = 0; j < pendingNewTodos.length; j++) {
            if (pendingNewTodos[j].uid === uid) return pendingNewTodos[j];
        }
        return null;
    }

    function _setTodoOverride(uid, patch) {
        var o = {};
        for (var k in todoOverrides) o[k] = todoOverrides[k];
        o[uid] = patch;
        todoOverrides = o;
    }

    function _clearTodoOverride(uid) {
        if (!todoOverrides.hasOwnProperty(uid)) return;
        var o = {};
        for (var k in todoOverrides) { if (k !== uid) o[k] = todoOverrides[k]; }
        todoOverrides = o;
    }

    function _addPendingTodo(entry) {
        pendingNewTodos = pendingNewTodos.concat([entry]);
    }

    function _removePendingTodo(tempUid) {
        pendingNewTodos = pendingNewTodos.filter(function (t) { return t.uid !== tempUid; });
    }

    function _addPendingEvent(entry) {
        pendingNewEvents = pendingNewEvents.concat([entry]);
    }

    function _removePendingEvent(tempKey) {
        pendingNewEvents = pendingNewEvents.filter(function (e) { return e.key !== tempKey; });
    }

    // --- Caché por fecha (para que hacer scroll por el mes no recalcule
    // todo cada frame). Se invalida cuando cambian `events` o cuando cambia
    // el día actual. ---

    property var dayCache: ({})
    property string lastCacheDay: isoDate(new Date())

    Timer {
        // Comprueba una vez por minuto si ha cambiado el día para invalidar
        // la caché; no es un timer de polling de archivos, solo del reloj.
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            var today = root.isoDate(new Date());
            if (today !== root.lastCacheDay) {
                root.lastCacheDay = today;
                root.dayCache = {};
            }
        }
    }

    onEventsChanged: dayCache = {}

    function dayCacheEntry(dateString) {
        if (dayCache.hasOwnProperty(dateString)) return dayCache[dateString];
        var matched = [];
        var evs = events;
        for (var i = 0; i < evs.length; i++) {
            var e = evs[i];
            if (e.startDate <= dateString && dateString <= e.endDate) matched.push(e);
        }
        var colors = [];
        var seen = {};
        for (var j = 0; j < matched.length; j++) {
            var c = matched[j].color;
            if (c && !seen[c]) { seen[c] = true; colors.push(c); }
        }
        var entry = { events: matched, colors: colors };
        var nc = {};
        for (var k in dayCache) nc[k] = dayCache[k];
        nc[dateString] = entry;
        dayCache = nc;
        return entry;
    }

    // --- Helpers ---

    function isoDate(d) {
        var y = d.getFullYear();
        var m = ("0" + (d.getMonth() + 1)).slice(-2);
        var dd = ("0" + d.getDate()).slice(-2);
        return y + "-" + m + "-" + dd;
    }

    function compareUpcoming(a, b) {
        if (a.startDate !== b.startDate) return a.startDate < b.startDate ? -1 : 1;
        if (a.allDay !== b.allDay) return a.allDay ? -1 : 1;
        var as = a.start || "", bs = b.start || "";
        if (as !== bs) return as < bs ? -1 : 1;
        return (a.title || "").localeCompare(b.title || "");
    }

    function mergeTodoOverrides(list) {
        if (Object.keys(todoOverrides).length === 0) return list;
        return list.map(function (t) {
            var ov = todoOverrides[t.uid];
            if (!ov) return t;
            var merged = {};
            for (var k in t) merged[k] = t[k];
            for (var k2 in ov) merged[k2] = ov[k2];
            return merged;
        });
    }

    function filterTodos(list) {
        var hidden = (Config.raw && Config.raw.hiddenLists) || [];
        if (hidden.length === 0) return list;
        return list.filter(function (t) { return hidden.indexOf(t.list) === -1; });
    }

    function expandAndFilterEvents() {
        var hidden = (Config.raw && Config.raw.hiddenCalendars) || [];
        var all = rawEvents.concat(pendingNewEvents);
        if (hidden.length === 0) return all;
        return all.filter(function (e) { return hidden.indexOf(e.calendar) === -1; });
    }

    // ---------------------------------------------------------------
    // Carga de archivos
    // ---------------------------------------------------------------

    Loader {
        id: fileLoader
        active: true
        sourceComponent: filesComponent
    }

    Component {
        id: filesComponent

        Item {
            FileView {
                id: eventsFile
                path: root.cacheDir + "/events.json"
                watchChanges: true
                onLoaded: root.handleEventsText(text())
                onFileChanged: root.handleEventsText(text())
                onLoadFailed: function (error) {
                    // Sin archivo todavía (p.ej. primer arranque antes del
                    // primer sync): no es un error fatal, simplemente no hay
                    // datos utilizables aún. No tocamos rawEvents.
                    console.log("DataStore: events.json no disponible todavía:", error);
                }
            }

            FileView {
                id: todosFile
                path: root.cacheDir + "/todos.json"
                watchChanges: true
                onLoaded: root.handleTodosText(text())
                onFileChanged: root.handleTodosText(text())
                onLoadFailed: function (error) {
                    console.log("DataStore: todos.json no disponible todavía:", error);
                }
            }

            FileView {
                id: statusFile
                path: root.cacheDir + "/status.json"
                watchChanges: true
                onLoaded: root.handleStatusText(text())
                onFileChanged: root.handleStatusText(text())
                onLoadFailed: function (error) {
                    console.log("DataStore: status.json no disponible todavía:", error);
                }
            }
        }
    }

    function handleEventsText(text) {
        // Parseo defensivo: si el JSON está a medias, corrupto, o con
        // `schema` distinto de 1, conservamos los datos anteriores.
        try {
            var data = JSON.parse(text);
            if (!data || data.schema !== 1 || !Array.isArray(data.events)) {
                console.warn("DataStore: events.json con schema inesperado, se conservan datos anteriores");
                return;
            }
            rawEvents = data.events;
            rawCalendars = Array.isArray(data.calendars) ? data.calendars : [];
            eventsLoadedOnce = true;
            // Los eventos "de verdad" ya llegaron: descartamos cualquier
            // fantasma optimista pendiente, esté o no reflejado todavía.
            pendingNewEvents = [];
        } catch (e) {
            console.warn("DataStore: events.json corrupto, se conservan datos anteriores:", e);
        }
    }

    function handleTodosText(text) {
        try {
            var data = JSON.parse(text);
            if (!data || data.schema !== 1 || !Array.isArray(data.todos)) {
                console.warn("DataStore: todos.json con schema inesperado, se conservan datos anteriores");
                return;
            }
            rawTodos = data.todos;
            rawLists = Array.isArray(data.lists) ? data.lists : [];
            todosLoadedOnce = true;
            pendingNewTodos = [];
            // Los overrides optimistas ya no hacen falta si la fila real ya
            // refleja el estado esperado; los que no encajen se limpian
            // igualmente en la próxima acción. Limpiamos todos para evitar
            // que un override viejo tape un cambio legítimo hecho fuera del
            // panel (p.ej. desde el iPhone).
            todoOverrides = {};
        } catch (e) {
            console.warn("DataStore: todos.json corrupto, se conservan datos anteriores:", e);
        }
    }

    function handleStatusText(text) {
        try {
            var data = JSON.parse(text);
            if (!data || data.schema !== 1) {
                console.warn("DataStore: status.json con schema inesperado, se conserva estado anterior");
                return;
            }
            rawStatus = data;
            statusLoadedOnce = true;
        } catch (e) {
            console.warn("DataStore: status.json corrupto, se conserva estado anterior:", e);
        }
    }
}
