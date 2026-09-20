// Tests de services/DataStore.qml contra tests/fixtures/ de verdad (leídos
// del disco por el stub de FileView, ver tests/qml/stubs/Quickshell/Io/FileView.qml).
//
// Escenarios usados (preparados por tests/run.sh en tests/qml/.tmp/):
//   cache-ok      -> events.json + todos.json + status.json (los "grandes": 10/8/3/3)
//   cache-corrupt -> copia privada de events.json, mutada a mitad de test

import QtQuick
import QtTest
import Quickshell as QS
import "../../quickshell/.config/quickshell/icloud-glass/services" as Services

TestCase {
    id: root
    name: "DataStore"

    function _cachePath(name) {
        return Qt.resolvedUrl("./.tmp/" + name).toString().replace("file://", "");
    }

    function _useScenario(name) {
        QS.Quickshell._setTestEnv({
            "HOME": "/nonexistent-home-for-tests",
            "ICLOUD_GLASS_CACHE_DIR": root._cachePath(name)
        });
    }

    function test_loadsTheThreeFixtures() {
        root._useScenario("cache-ok");
        tryVerify(function () { return Services.DataStore.events.length === 10; }, 3000);
        compare(Services.DataStore.todos.length, 8);
        compare(Services.DataStore.calendars.length, 3);
        compare(Services.DataStore.lists.length, 3);
        verify(Services.DataStore.ready);
    }

    function test_eventsOnLisboaTrip() {
        root._useScenario("cache-ok");
        tryVerify(function () { return Services.DataStore.events.length === 10; }, 3000);

        var on22 = Services.DataStore.eventsOn("2026-09-22");
        var titles22 = on22.map(function (e) { return e.title; });
        verify(titles22.indexOf("Viaje a Lisboa") !== -1,
               "eventsOn(2026-09-22) debería incluir 'Viaje a Lisboa' (multi-día 09-21..09-24); tenía: " + JSON.stringify(titles22));

        var on25 = Services.DataStore.eventsOn("2026-09-25");
        var titles25 = on25.map(function (e) { return e.title; });
        verify(titles25.indexOf("Viaje a Lisboa") === -1,
               "eventsOn(2026-09-25) NO debería incluir 'Viaje a Lisboa'; tenía: " + JSON.stringify(titles25));
    }

    // "hoy" real del contenedor es 2026-09-20 (comprobado con `date`); todos
    // los eventos fechados el 2026-09-19 (generated de los fixtures) ya
    // terminaron y no deben aparecer en upcoming().
    function test_upcomingExcludesFinishedEvents() {
        root._useScenario("cache-ok");
        tryVerify(function () { return Services.DataStore.events.length === 10; }, 3000);

        var up = Services.DataStore.upcoming(5);
        verify(up.length > 0, "upcoming(5) no debería estar vacío con los fixtures 'ok'");
        var titles = up.map(function (e) { return e.title; });
        verify(titles.indexOf("Festivo local") === -1, "un evento all-day de ayer no debe salir en upcoming(): " + JSON.stringify(titles));
        verify(titles.indexOf("Reunión de equipo") === -1, "un evento de ayer ya terminado no debe salir en upcoming(): " + JSON.stringify(titles));
        verify(titles.indexOf("Cena cancelada") === -1, "un evento de ayer ya terminado no debe salir en upcoming(): " + JSON.stringify(titles));
        verify(titles.indexOf("Viaje a Lisboa") !== -1, "el viaje a Lisboa (futuro) debería salir en upcoming(): " + JSON.stringify(titles));

        var nowMs = Date.now();
        for (var i = 0; i < up.length; i++) {
            var e = up[i];
            if (e.allDay) {
                verify(e.endDate >= "2026-09-20", "evento all-day ya terminado colado en upcoming(): " + e.title);
            } else if (e.end) {
                verify(Date.parse(e.end) >= nowMs, "evento con hora ya terminado colado en upcoming(): " + e.title);
            }
        }
    }

    function test_corruptJsonMidLoadKeepsOldData() {
        root._useScenario("cache-corrupt");
        tryVerify(function () { return Services.DataStore.events.length === 10; }, 3000);
        var beforeEvents = Services.DataStore.events;
        var beforeCount = beforeEvents.length;
        compare(beforeCount, 10);

        // Corrompemos events.json A MITAD DE CARGA (JSON truncado a propósito)
        // escribiendo directamente en el archivo que DataStore está vigilando.
        var putDone = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) putDone = true;
        };
        xhr.open("PUT", Qt.resolvedUrl("./.tmp/cache-corrupt/events.json"), true);
        xhr.send('{"schema": 1, "events": [ { "uid": "roto"');
        tryVerify(function () { return putDone; }, 2000);

        // Le damos tiempo al watcher (sondeo cada ~40ms en el stub) a reaccionar.
        wait(300);

        // No debe haber lanzado excepción (si la hubiera lanzado, qmltestrunner
        // ya habría marcado un error de QML en el log — ver tests/run.sh) y los
        // datos anteriores deben seguir intactos.
        compare(Services.DataStore.events.length, beforeCount,
                "un events.json corrupto a mitad de carga no debe cambiar el número de eventos");
        compare(Services.DataStore.events[0].uid, beforeEvents[0].uid);
    }
}
