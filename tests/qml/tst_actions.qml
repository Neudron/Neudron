// Tests de services/Actions.qml contra el stub de Quickshell.Io.Process
// (tests/qml/stubs/Quickshell/Io/Process.qml), que NO ejecuta nada de
// verdad: solo registra en Quickshell.Io.ProcessRegistry qué comando se
// habría lanzado. Así se puede afirmar EXACTAMENTE qué CLI invoca cada
// acción, tal y como exige docs/CONTRACTS.md §9.

import QtQuick
import QtTest
import Quickshell as QS
import Quickshell.Io as QSIo
import "../../quickshell/.config/quickshell/icloud-glass/services" as Services

TestCase {
    id: root
    name: "Actions"

    function _cachePath(name) {
        return Qt.resolvedUrl("./.tmp/" + name).toString().replace("file://", "");
    }

    function initTestCase() {
        QS.Quickshell._setTestEnv({
            "HOME": "/nonexistent-home-for-tests",
            "ICLOUD_GLASS_CACHE_DIR": root._cachePath("cache-ok")
        });
        tryVerify(function () { return Services.DataStore.todos.length === 8; }, 3000);
    }

    function init() {
        // Deja que cualquier proceso stub en vuelo de un test anterior
        // "termine" (Qt.callLater) antes de empezar el siguiente test, para
        // que ProcessRegistry.reset() y las aserciones sobre `busy` no
        // dependan de una carrera con la limpieza asíncrona del anterior.
        tryVerify(function () { return !Services.Actions.busy; }, 3000);
        QSIo.ProcessRegistry.reset();
        // DataStore es un singleton compartido por TODOS los tests de este
        // archivo (a diferencia del engine, que es nuevo por archivo — ver
        // el informe). Los overrides optimistas de completeTodo() sí
        // persisten entre funciones test_*, así que cada test arranca desde
        // un estado conocido limpiando los uids que va a tocar.
        Services.DataStore._clearTodoOverride("todo-overdue-1");
        Services.DataStore._clearTodoOverride("todo-done-1");
    }

    // Requisito explícito del encargo: "Pulsar el check de un recordatorio
    // invoca exactamente [\"icloud-glass-write\",\"todo-done\",\"<uid>\"]".
    function test_completeTodoInvokesExactWriteCommand() {
        Services.Actions.completeTodo("todo-overdue-1", true);
        tryVerify(function () { return QSIo.ProcessRegistry.calls.length >= 1; }, 3000);
        compare(QSIo.ProcessRegistry.calls[0].command, ["icloud-glass-write", "todo-done", "todo-overdue-1"]);
    }

    function test_undoCompleteAppendsUndoFlag() {
        Services.Actions.completeTodo("todo-done-1", false);
        tryVerify(function () { return QSIo.ProcessRegistry.calls.length >= 1; }, 3000);
        compare(QSIo.ProcessRegistry.calls[0].command, ["icloud-glass-write", "todo-done", "todo-done-1", "--undo"]);
    }

    // Tras un éxito, Actions debe además lanzar icloud-glass-refresh
    // (docs/CONTRACTS.md §9, último párrafo).
    function test_successTriggersRefresh() {
        Services.Actions.completeTodo("todo-overdue-1", true);
        tryVerify(function () {
            return QSIo.ProcessRegistry.calls.length >= 2;
        }, 3000);
        var commands = QSIo.ProcessRegistry.calls.map(function (c) { return c.command[0]; });
        verify(commands.indexOf("icloud-glass-refresh") !== -1,
               "tras completar un todo debería lanzarse icloud-glass-refresh; comandos vistos: " + JSON.stringify(commands));
    }

    // Actions es "optimista": aplica el cambio local al instante...
    function test_optimisticUpdateAppliesImmediately() {
        var before = Services.DataStore._findTodo("todo-overdue-1");
        verify(before && before.completed === false);
        Services.Actions.completeTodo("todo-overdue-1", true);
        // Inmediatamente (sin esperar a que "termine" el proceso stub) ya
        // debe verse completado en DataStore, vía el override optimista.
        var updated = Services.DataStore.todos.filter(function (t) { return t.uid === "todo-overdue-1"; })[0];
        verify(updated.completed === true, "completeTodo debe reflejarse al instante, antes de que 'termine' el proceso");
    }

    // ...y si el proceso "sale" con código != 0, revierte y emite actionFailed.
    function test_failedWriteRevertsAndEmitsActionFailed() {
        QSIo.ProcessRegistry.setResult(["icloud-glass-write", "todo-done"], {
            exitCode: 1,
            stdout: "",
            stderr: "No existe ninguna tarea con ese UID."
        });

        var failedWhat = "";
        var failedMessage = "";
        var gotFailed = false;
        var conn = function (what, message) {
            gotFailed = true;
            failedWhat = what;
            failedMessage = message;
        };
        Services.Actions.actionFailed.connect(conn);

        Services.Actions.completeTodo("todo-overdue-1", true);
        tryVerify(function () { return gotFailed; }, 3000);
        Services.Actions.actionFailed.disconnect(conn);

        compare(failedWhat, "completeTodo");
        verify(failedMessage.indexOf("No existe ninguna tarea con ese UID.") !== -1,
               "el mensaje de fallo debería incluir el stderr real: " + failedMessage);

        var reverted = Services.DataStore.todos.filter(function (t) { return t.uid === "todo-overdue-1"; })[0];
        compare(reverted.completed, false, "tras un fallo, completeTodo debe revertir el cambio optimista");
    }

    function test_busyReflectsInFlightProcesses() {
        compare(Services.Actions.busy, false);
        Services.Actions.completeTodo("todo-overdue-1", true);
        // Justo después de lanzar la acción debería haber al menos un
        // proceso en vuelo (el propio icloud-glass-write).
        verify(Services.Actions.busy, "busy debería ser true mientras el proceso stub no ha 'terminado'");
        tryVerify(function () { return !Services.Actions.busy; }, 3000);
    }
}
