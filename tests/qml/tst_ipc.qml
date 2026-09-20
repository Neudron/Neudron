// Tests de services/Ipc.qml.
//
// FALLO REAL ENCONTRADO (documentado también en el informe de la tarea):
// src/io/ipchandler.hpp del mirror oficial de Quickshell dice, TEXTUALMENTE,
// en el comentario Doxygen de IpcHandler:
//   "Argument and return types must be explicitly specified or they will
//    not be registered."
// y su propio ejemplo anota SIEMPRE el tipo de retorno, incluso ": void"
// para funciones que no devuelven nada:
//   function setColor(color: color): void { rect.color = color; }
// Las 4 funciones de Ipc.qml (toggle/open/close/refresh) no llevaban tipo de
// retorno -> con Quickshell de verdad, NINGUNA se habría registrado para IPC,
// y `qs ipc call panel toggle` (documentado en el propio comentario de
// Ipc.qml) habría fallado en silencio. Se corrigió añadiendo `: void` a las 4.
//
// LÍMITE HONESTO de este test: un stub QML puro no puede reproducir en
// runtime que una función sin tipo "no se registre" para IPC — esa
// distinción vive a nivel de QMetaObject en el motor C++ real y es invisible
// para JS/QML (ver la nota en tests/qml/stubs/Quickshell/Io/IpcHandler.qml).
// Por eso la regresión se comprueba de forma ESTÁTICA, leyendo el propio
// texto fuente de Ipc.qml y validando que cada función declarada dentro del
// bloque IpcHandler lleva anotación de tipo de retorno explícita. Es un
// chequeo de texto, no de comportamiento — documentado como tal.

import QtQuick
import QtTest
import Quickshell as QS
import "../../quickshell/.config/quickshell/icloud-glass/services" as Services

TestCase {
    id: root
    name: "Ipc"

    readonly property url ipcSourceUrl: Qt.resolvedUrl(
        "../../quickshell/.config/quickshell/icloud-glass/services/Ipc.qml")

    function _readSource(url) {
        var xhr = new XMLHttpRequest();
        var done = false;
        var text = "";
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) { text = xhr.responseText; done = true; }
        };
        xhr.open("GET", url, true);
        xhr.send();
        tryVerify(function () { return done; }, 2000);
        return text;
    }

    // Regresión estática del fallo real descrito arriba: todas las
    // funciones declaradas dentro de IpcHandler deben anotar su tipo de
    // retorno, o Quickshell real no las registraría para `qs ipc call`.
    function test_allIpcHandlerFunctionsHaveExplicitReturnType() {
        var src = root._readSource(root.ipcSourceUrl);
        var ipcHandlerStart = src.indexOf("IpcHandler {");
        verify(ipcHandlerStart !== -1, "Ipc.qml debería declarar un bloque IpcHandler { ... }");
        var block = src.substring(ipcHandlerStart);

        var fnRe = /function\s+(\w+)\s*\(([^)]*)\)\s*(:\s*[A-Za-z_][A-Za-z0-9_]*)?\s*\{/g;
        var match;
        var checked = 0;
        while ((match = fnRe.exec(block)) !== null) {
            checked += 1;
            var name = match[1];
            var returnAnnotation = match[3];
            verify(!!returnAnnotation,
                   "function " + name + "(...) dentro de IpcHandler no anota tipo de retorno " +
                   "(':  void' | ':  color' | ...) — con Quickshell real NO se registraría para IPC " +
                   "('Argument and return types must be explicitly specified or they will not be " +
                   "registered', src/io/ipchandler.hpp).");
        }
        verify(checked >= 4, "se esperaban al menos 4 funciones (toggle/open/close/refresh) en IpcHandler; se vieron " + checked);
    }

    // Ipc.qml no le da un `id` al IpcHandler interno (no hace falta para su
    // propio funcionamiento). Para llamar a sus funciones desde el test sin
    // tocar el archivo de producción solo para "hacerlo testeable", nos
    // apoyamos en que nuestro stub de Singleton (ver
    // tests/qml/stubs/Quickshell/Singleton.qml) replica fielmente el
    // `default property list<QObject> children` real de
    // Quickshell.Singleton/Scope: el IpcHandler, al ser el único hijo
    // declarado dentro de `Singleton { ... }` en Ipc.qml, cae ahí solo.
    function _handler() {
        return Services.Ipc.children[0];
    }

    function test_toggleFlipsPanelOpenAndEmitsSignals() {
        var openedCount = 0, closedCount = 0;
        var onOpened = function () { openedCount += 1; };
        var onClosed = function () { closedCount += 1; };
        Services.Ipc.panelOpened.connect(onOpened);
        Services.Ipc.panelClosed.connect(onClosed);

        compare(Services.Ipc.panelOpen, false);
        root._handler().toggle();
        compare(Services.Ipc.panelOpen, true);
        compare(openedCount, 1);

        root._handler().toggle();
        compare(Services.Ipc.panelOpen, false);
        compare(closedCount, 1);

        Services.Ipc.panelOpened.disconnect(onOpened);
        Services.Ipc.panelClosed.disconnect(onClosed);
    }

    function test_openAndCloseAreIdempotent() {
        Services.Ipc.panelOpen = false;
        var openedCount = 0;
        var onOpened = function () { openedCount += 1; };
        Services.Ipc.panelOpened.connect(onOpened);

        root._handler().open();
        root._handler().open(); // segunda llamada: no debe re-emitir panelOpened
        compare(Services.Ipc.panelOpen, true);
        compare(openedCount, 1);

        Services.Ipc.panelOpened.disconnect(onOpened);
        root._handler().close();
        compare(Services.Ipc.panelOpen, false);
    }

    function test_refreshEmitsRefreshRequested() {
        var count = 0;
        var onRefresh = function () { count += 1; };
        Services.Ipc.refreshRequested.connect(onRefresh);
        root._handler().refresh();
        compare(count, 1);
        Services.Ipc.refreshRequested.disconnect(onRefresh);
    }
}
