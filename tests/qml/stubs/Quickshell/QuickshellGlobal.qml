// STUB del singleton global `Quickshell` (Quickshell.Quickshell), fuente de
// verdad: src/core/qmlglobal.hpp del mirror oficial (clase QuickshellGlobal,
// QML_SINGLETON, QML_NAMED_ELEMENT(Quickshell)). Superficie usada de verdad
// por icloud-glass: `env(name)` (Config.qml, DataStore.qml) y `screens`
// (GlassPanel.qml, vía Quickshell.screens.find(...)).
//
// DISEÑO DELIBERADO para `env()`: la API real envuelve qgetenv/QProcessEnvironment
// en C++; QML puro no tiene forma portable de leer variables de entorno del
// proceso. En vez de intentar imitar eso leyendo /proc/self/environ (frágil:
// los archivos de /proc no tienen tamaño real y romben la lectura síncrona
// de XMLHttpRequest, verificado en este mismo arnés), este stub expone un
// mapa interno que cada test rellena explícitamente ANTES de referenciar
// cualquier Singleton de icloud-glass con _setTestEnv(...). Esto es MÁS
// determinista que depender del entorno real del proceso (nada de timing de
// E/S), a costa de no ser una réplica de bajo nivel — se documenta aquí y en
// el informe final como una simplificación del stub, no como el
// comportamiento real de Quickshell.env().
pragma Singleton
import QtQml

QtObject {
    id: root

    property var _env: ({})
    property var _screens: []

    // --- superficie real ---------------------------------------------------
    function env(name) {
        return root._env.hasOwnProperty(name) ? root._env[name] : null;
    }

    readonly property var screens: root._screens

    function execDetached(context) {
        // No-op deliberado: ningún QML de icloud-glass lo usa hoy y lanzar un
        // proceso de verdad violaría el requisito de que el stub de proceso
        // no ejecute nada fuera de ProcessRegistry.
    }

    // --- ganchos SOLO para tests (no forman parte de la API real) ----------
    function _setTestEnv(map) {
        root._env = map || {};
    }

    function _mergeTestEnv(map) {
        var merged = {};
        for (var k in root._env) merged[k] = root._env[k];
        for (var k2 in (map || {})) merged[k2] = map[k2];
        root._env = merged;
    }

    function _setTestScreens(list) {
        root._screens = list || [];
    }
}
