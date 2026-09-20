// "Navegar meses y días no rompe selectedDate" (requisito explícito del
// encargo). Cubre CalendarWidget.qml (navegación de mes + teclado) y
// CombinedPanel.qml (flechas de día, que delegan en CalendarWidget).

import QtQuick
import QtTest
import Quickshell as QS
import "../../quickshell/.config/quickshell/icloud-glass/services" as Services
import "../../quickshell/.config/quickshell/icloud-glass/modules" as Modules

TestCase {
    id: root
    name: "CalendarNav"

    readonly property url calendarUrl: Qt.resolvedUrl(
        "../../quickshell/.config/quickshell/icloud-glass/modules/CalendarWidget.qml")
    readonly property url combinedPanelUrl: Qt.resolvedUrl(
        "../../quickshell/.config/quickshell/icloud-glass/modules/CombinedPanel.qml")

    function _cachePath(name) {
        return Qt.resolvedUrl("./.tmp/" + name).toString().replace("file://", "");
    }

    function initTestCase() {
        QS.Quickshell._setTestEnv({
            "HOME": "/nonexistent-home-for-tests",
            "ICLOUD_GLASS_CACHE_DIR": root._cachePath("cache-ok")
        });
        tryVerify(function () { return Services.DataStore.events.length === 10; }, 3000);
    }

    property QtObject _current: null
    function cleanup() {
        if (root._current) { root._current.destroy(); root._current = null; }
    }

    function _instantiate(url) {
        var component = Qt.createComponent(url);
        tryVerify(function () { return component.status === Component.Ready || component.status === Component.Error; }, 3000);
        compare(component.errorString(), "");
        var obj = component.createObject(root);
        verify(obj !== null);
        root._current = obj;
        return obj;
    }

    readonly property var dateRe: /^\d{4}-\d{2}-\d{2}$/

    function test_changeViewMonthKeepsSelectedDateValid() {
        var cal = root._instantiate(root.calendarUrl);
        var initialSelected = cal.selectedDate;
        verify(root.dateRe.test(initialSelected));

        for (var i = 0; i < 14; i++) {
            cal.changeViewMonth(1);
        }
        // Navegar el mes VISIBLE no debe tocar selectedDate (son
        // independientes: CalendarWidget.qml lo documenta explícitamente).
        compare(cal.selectedDate, initialSelected, "cambiar el mes visible no debería alterar selectedDate");
        verify(root.dateRe.test(cal.selectedDate));

        for (var j = 0; j < 20; j++) {
            cal.changeViewMonth(-1);
        }
        compare(cal.selectedDate, initialSelected);
        compare(cal.cells.length, 42, "la rejilla siempre reserva 42 celdas, incluso tras navegar 20 meses");
    }

    function test_selectCellUpdatesSelectedDateAndView() {
        var cal = root._instantiate(root.calendarUrl);
        cal.selectCell("2026-11-03");
        compare(cal.selectedDate, "2026-11-03");
        compare(cal.viewYear, 2026);
        compare(cal.viewMonth, 11);
        verify(cal.cells.some(function (c) { return c.iso === "2026-11-03" && c.inMonth; }));
    }

    function test_keyboardNavigationAcrossMonthBoundaryKeepsValidFocusDate() {
        var cal = root._instantiate(root.calendarUrl);
        cal.selectCell("2026-09-30");
        cal.focusDate = "2026-09-30";
        // Cruza a octubre: focusDate debe seguir siendo una fecha válida y
        // el mes visible debe seguir a focusDate.
        cal.moveFocusByDays(1);
        compare(cal.focusDate, "2026-10-01");
        compare(cal.viewYear, 2026);
        compare(cal.viewMonth, 10);
        verify(root.dateRe.test(cal.focusDate));

        // Enter selecciona la fecha con foco.
        cal.selectFocusDate();
        compare(cal.selectedDate, "2026-10-01");

        // Navegar por meses con teclado (PageUp/PageDown) tampoco debe
        // producir una fecha inválida, incluso cruzando límites de fin de mes
        // (31 oct -> 30 nov: el día se recorta, nunca se desborda a diciembre).
        cal.focusDate = "2026-10-31";
        cal.moveFocusByMonths(1);
        compare(cal.viewMonth, 11);
        verify(root.dateRe.test(cal.focusDate));
        var parts = cal.focusDate.split("-").map(function (n) { return parseInt(n, 10); });
        compare(parts[1], 11, "moveFocusByMonths no debe desbordar a diciembre por un día 31 inexistente en noviembre");
    }

    function test_goTodayResetsToTodayAndSelectsIt() {
        var cal = root._instantiate(root.calendarUrl);
        cal.changeViewMonth(5);
        cal.goToday();
        compare(cal.selectedDate, cal.todayIso);
        compare(cal.focusDate, cal.todayIso);
        compare(cal.viewYear, new Date().getFullYear());
        compare(cal.viewMonth, new Date().getMonth() + 1);
    }

    // CombinedPanel.qml: las flechas ◀/▶ del día seleccionado (shiftDay)
    // delegan en CalendarWidget.selectedDate; comprobamos que encadenar
    // varios días adelante y atrás nunca deja selectedDate en un valor
    // inválido (p.ej. cruzando el cambio de mes o el DST del 25-10-2026,
    // que es justo uno de los casos duros de los fixtures).
    function test_combinedPanelShiftDayNeverBreaksSelectedDate() {
        var panel = root._instantiate(root.combinedPanelUrl);
        panel.selectDate("2026-10-20");
        compare(panel.selectedDate, "2026-10-20");

        var seen = [panel.selectedDate];
        for (var i = 0; i < 10; i++) {
            var next = panel.shiftDay(panel.selectedDate, 1);
            verify(root.dateRe.test(next), "shiftDay debe devolver siempre YYYY-MM-DD, dio: " + next);
            panel.selectDate(next);
            seen.push(panel.selectedDate);
        }
        // 10 días desde el 20-10 deben llegar limpiamente al 30-10 (cruzando
        // el DST del 25-10-2026 sin romperse: shiftDay opera en fechas
        // locales de calendario, no en instantes, así que el cambio de hora
        // no debe alterar el conteo de días).
        compare(panel.selectedDate, "2026-10-30");
        compare(seen.length, 11);

        for (var j = 0; j < 15; j++) {
            panel.selectDate(panel.shiftDay(panel.selectedDate, -1));
        }
        compare(panel.selectedDate, "2026-10-15");
        verify(root.dateRe.test(panel.selectedDate));
    }
}
