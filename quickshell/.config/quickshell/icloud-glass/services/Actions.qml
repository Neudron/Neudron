pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Actions: ejecuta las acciones de escritura (completar/crear todos, crear
// eventos, forzar sync) llamando a los binarios externos que instala A1
// (`todo`, `khal`, `icloud-glass-refresh`, `icloud-glass-sync`) vía
// Quickshell.Io.Process. Es optimista: aplica el cambio en DataStore al
// instante y, si el proceso termina con código != 0, revierte y emite
// actionFailed con el motivo real (tomado de stderr cuando lo hay).
//
// API pública (congelada, ver docs/CONTRACTS.md §6):
//   completeTodo(uid, completed), newTodo(listName, summary, dueIso),
//   newEvent(calendarName, title, startIso, endIso, allDay), sync(),
//   actionFailed(what, message), actionSucceeded(what), busy
Singleton {
    id: root

    // Contador de operaciones en vuelo; `busy` es true mientras haya alguna.
    // Así una acción que falla o cuyo proceso muere inesperadamente nunca
    // deja `busy` colgado: cada Process, gane o pierda, decrementa el
    // contador exactamente una vez (ver runProcess).
    property int inFlight: 0
    readonly property bool busy: inFlight > 0

    signal actionFailed(string what, string message)
    signal actionSucceeded(string what)

    function completeTodo(uid, completed) {
        var previous = DataStore._findTodo(uid);
        var previousOverride = DataStore.todoOverrides.hasOwnProperty(uid)
            ? DataStore.todoOverrides[uid] : null;

        DataStore._setTodoOverride(uid, {
            completed: completed,
            completedAt: completed ? new Date().toISOString() : null
        });

        runProcess(["todo", completed ? "done" : "undo", uid], function (ok, exitCode, stderrText) {
            if (ok) {
                root.actionSucceeded("completeTodo");
                refreshAfterWrite();
            } else {
                // Revertimos al override anterior (o lo quitamos si no había).
                if (previousOverride) DataStore._setTodoOverride(uid, previousOverride);
                else DataStore._clearTodoOverride(uid);
                root.actionFailed("completeTodo", describeFailure(
                    "No se pudo " + (completed ? "completar" : "reabrir") + " el recordatorio", stderrText, exitCode));
            }
        });
    }

    function newTodo(listName, summary, dueIso) {
        var tempUid = "pending-todo-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
        var ghost = {
            uid: tempUid,
            summary: summary,
            list: listName,
            color: Config.listColor(listName),
            completed: false,
            completedAt: null,
            due: dueIso || null,
            dueDate: dueIso ? dueIso.substring(0, 10) : null,
            dueAllDay: false,
            overdue: false,
            priority: 0,
            priorityLabel: "none",
            percent: 0,
            description: null,
            categories: [],
            created: new Date().toISOString()
        };
        DataStore._addPendingTodo(ghost);

        var args = ["todo", "new", "--list", listName];
        if (dueIso) args.push("--due", dueIso);
        args.push(summary);

        runProcess(args, function (ok, exitCode, stderrText) {
            if (ok) {
                root.actionSucceeded("newTodo");
                refreshAfterWrite();
            } else {
                DataStore._removePendingTodo(tempUid);
                root.actionFailed("newTodo", describeFailure(
                    "No se pudo crear el recordatorio «" + summary + "»", stderrText, exitCode));
            }
        });
    }

    function newEvent(calendarName, title, startIso, endIso, allDay) {
        var tempKey = "pending-event-" + Date.now() + "-" + Math.floor(Math.random() * 1e6);
        var startDate = (startIso || "").substring(0, 10);
        var endDate = (endIso || startIso || "").substring(0, 10);
        var ghost = {
            uid: tempKey,
            key: tempKey,
            title: title,
            calendar: calendarName,
            color: Config.calendarColor(calendarName),
            allDay: !!allDay,
            start: allDay ? null : startIso,
            end: allDay ? null : endIso,
            startDate: startDate,
            endDate: endDate,
            durationMinutes: null,
            location: null,
            description: null,
            recurring: false,
            status: "CONFIRMED",
            cancelled: false,
            url: null,
            categories: []
        };
        DataStore._addPendingEvent(ghost);

        var args = ["khal", "new", "--calendar", calendarName];
        if (allDay) {
            args.push(startDate);
            if (endDate !== startDate) args.push(endDate);
            args.push(title);
        } else {
            args.push(startIso, endIso, title);
        }

        runProcess(args, function (ok, exitCode, stderrText) {
            if (ok) {
                root.actionSucceeded("newEvent");
                refreshAfterWrite();
            } else {
                DataStore._removePendingEvent(tempKey);
                root.actionFailed("newEvent", describeFailure(
                    "No se pudo crear el evento «" + title + "»", stderrText, exitCode));
            }
        });
    }

    function sync() {
        runProcess(["icloud-glass-sync"], function (ok, exitCode, stderrText) {
            if (ok) root.actionSucceeded("sync");
            else root.actionFailed("sync", describeFailure("No se pudo sincronizar con iCloud", stderrText, exitCode));
        });
    }

    // --- Internals ---

    function refreshAfterWrite() {
        // Tras una escritura, pedimos que se regenere la caché para que
        // events.json/todos.json reflejen el cambio real; DataStore lo
        // recogerá solo (watchChanges) y limpiará los fantasmas/overrides.
        runProcess(["icloud-glass-refresh"], function (ok, exitCode, stderrText) {
            if (!ok) {
                console.warn("Actions: icloud-glass-refresh terminó con error:", exitCode, stderrText);
            }
        });
    }

    function describeFailure(prefix, stderrText, exitCode) {
        var detail = (stderrText || "").trim();
        if (detail.length > 0) {
            // Nos quedamos con la última línea no vacía: suele ser el
            // mensaje de error más concreto de las herramientas CLI.
            var lines = detail.split("\n").filter(function (l) { return l.trim().length > 0; });
            var lastLine = lines.length > 0 ? lines[lines.length - 1].trim() : detail;
            return prefix + ": " + lastLine;
        }
        return prefix + " (código de salida " + exitCode + ", sin más detalle del proceso)";
    }

    // Ejecuta `commandArray` como Process (nunca por shell: cada elemento es
    // un argumento literal, así que texto libre del usuario con comillas,
    // `;` o acentos nunca se interpreta). `callback(ok, exitCode, stderrText)`
    // se llama exactamente una vez, tanto si el proceso termina normalmente
    // como si falla al arrancar.
    function runProcess(commandArray, callback) {
        inFlight += 1;
        var finished = false;
        var finish = function (ok, exitCode, stderrText) {
            if (finished) return;
            finished = true;
            inFlight = Math.max(0, inFlight - 1);
            callback(ok, exitCode, stderrText);
        };

        var qml =
            'import Quickshell.Io\n' +
            'Process {\n' +
            '    stdout: StdioCollector {}\n' +
            '    stderr: StdioCollector {}\n' +
            '}\n';

        var proc;
        try {
            proc = Qt.createQmlObject(qml, root, "ActionsDynamicProcess");
        } catch (e) {
            finish(false, -1, "No se pudo lanzar el proceso: " + e);
            return;
        }

        proc.command = commandArray;

        proc.exited.connect(function (exitCode, exitStatus) {
            var errText = "";
            try { errText = proc.stderr.text || ""; } catch (e2) { errText = ""; }
            finish(exitCode === 0, exitCode, errText);
            proc.destroy();
        });

        try {
            proc.running = true;
        } catch (e3) {
            finish(false, -1, "No se pudo iniciar el proceso: " + e3);
            try { proc.destroy(); } catch (e4) {}
        }
    }
}
