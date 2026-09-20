// Instancia modules/CombinedPanel.qml (y, con él, todo su árbol: States,
// CalendarWidget, EventList, RemindersWidget, QuickAdd, GlassSurface con el
// stub no-op de QtQuick.Effects.MultiEffect) contra CADA variante de estado
// que pide el encargo: ok, error-network (-> stale, hay caché), error-auth
// (-> error, sin caché usable), syncing, events-empty, todos-empty.
//
// El criterio de "sin un solo error de QML" NO se limita a
// Component.errorString() (que solo cubre errores de COMPILACIÓN): los
// warnings de runtime (binding loops, TypeError, propiedades inexistentes,
// ...) se emiten por qWarning() a la salida del proceso, así que la
// comprobación real y completa de "cero errores" vive en tests/run.sh, que
// analiza TODA la salida de qmltestrunner. Este archivo se limita a afirmar
// que cada Component queda Ready y que el árbol expone lo que se espera por
// estado.

import QtQuick
import QtTest
import Quickshell as QS
import "../../quickshell/.config/quickshell/icloud-glass/services" as Services
import "../../quickshell/.config/quickshell/icloud-glass/components" as Components

TestCase {
    id: root
    name: "CombinedPanel"

    readonly property url combinedPanelUrl: Qt.resolvedUrl(
        "../../quickshell/.config/quickshell/icloud-glass/modules/CombinedPanel.qml")

    property QtObject _current: null

    function _cachePath(name) {
        return Qt.resolvedUrl("./.tmp/" + name).toString().replace("file://", "");
    }

    function _useScenario(dirName) {
        QS.Quickshell._setTestEnv({
            "HOME": "/nonexistent-home-for-tests",
            "ICLOUD_GLASS_CACHE_DIR": root._cachePath(dirName)
        });
    }

    function cleanup() {
        if (root._current) {
            root._current.destroy();
            root._current = null;
        }
    }

    // Crea un CombinedPanel de verdad (no un doble), esperando a que el
    // Component compile y quede Ready, y lo deja en root._current.
    function _instantiate() {
        var component = Qt.createComponent(root.combinedPanelUrl);
        tryVerify(function () {
            return component.status === Component.Ready || component.status === Component.Error;
        }, 3000);
        compare(component.errorString(), "");
        compare(component.status, Component.Ready);
        var obj = component.createObject(root);
        verify(obj !== null, "CombinedPanel.createObject() no debería devolver null");
        root._current = obj;
        return obj;
    }

    function test_scenario_ok() {
        root._useScenario("cache-ok");
        tryVerify(function () { return Services.DataStore.status.state === "ok" && Services.DataStore.events.length === 10; }, 3000);
        var panel = root._instantiate();
        verify(!panel.isStale, "estado 'ok' no debería marcarse como stale");
    }

    function test_scenario_errorNetwork_showsStaleBanner() {
        root._useScenario("cache-error-network");
        tryVerify(function () { return Services.DataStore.status.state === "stale" && Services.DataStore.events.length === 10; }, 3000);
        var panel = root._instantiate();
        verify(panel.isStale, "state 'stale' debería marcar isStale=true (la caché se sigue mostrando)");
        compare(Services.DataStore.events.length, 10, "en 'stale' los datos en caché se siguen mostrando, no se borran");
    }

    function test_scenario_errorAuth_showsErrorAndNoUsableCache() {
        root._useScenario("cache-error-auth");
        // OJO: el valor por defecto de DataStore.rawStatus (antes de que
        // cargue NINGÚN status.json real) YA tiene state:"error" (con
        // errorKind:null) — así que esperar solo state==="error" puede dar
        // un falso positivo con ese fallback y no con el fixture real.
        // Esperamos errorKind, que el fallback nunca tiene, para confirmar
        // que de verdad se cargó tests/fixtures/status-error-auth.json.
        tryVerify(function () { return Services.DataStore.status.errorKind === "auth"; }, 3000);
        var panel = root._instantiate();
        verify(panel.isStale, "state 'error' también debe activar el banner (isStale cubre stale Y error)");
        compare(Services.DataStore.status.errorKind, "auth");
    }

    function test_scenario_syncing() {
        root._useScenario("cache-syncing");
        tryVerify(function () { return Services.DataStore.status.state === "syncing"; }, 3000);
        var panel = root._instantiate();
        // syncing no es stale ni error: el banner de arriba no debe activarse por eso.
        verify(!panel.isStale, "state 'syncing' no debería marcarse como isStale");
    }

    function test_scenario_eventsEmpty() {
        root._useScenario("cache-events-empty");
        tryVerify(function () { return Services.DataStore.events.length === 0 && Services.DataStore.todos.length === 8; }, 3000);
        var panel = root._instantiate();
        verify(panel !== null);
    }

    function test_scenario_todosEmpty() {
        root._useScenario("cache-todos-empty");
        tryVerify(function () { return Services.DataStore.todos.length === 0 && Services.DataStore.events.length === 10; }, 3000);
        var panel = root._instantiate();
        verify(panel !== null);
    }
}
