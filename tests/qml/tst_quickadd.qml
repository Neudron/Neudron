// Test de modules/QuickAdd.qml: "QuickAdd con texto sin enviar pide
// confirmación al cerrar" (requisito explícito del encargo).

import QtQuick
import QtTest
import Quickshell as QS
import "../../quickshell/.config/quickshell/icloud-glass/services" as Services
import "../../quickshell/.config/quickshell/icloud-glass/modules" as Modules

TestCase {
    id: root
    name: "QuickAdd"

    readonly property url quickAddUrl: Qt.resolvedUrl(
        "../../quickshell/.config/quickshell/icloud-glass/modules/QuickAdd.qml")

    function _cachePath(name) {
        return Qt.resolvedUrl("./.tmp/" + name).toString().replace("file://", "");
    }

    function initTestCase() {
        QS.Quickshell._setTestEnv({
            "HOME": "/nonexistent-home-for-tests",
            "ICLOUD_GLASS_CACHE_DIR": root._cachePath("cache-ok")
        });
        tryVerify(function () { return Services.DataStore.lists.length === 3; }, 3000);
    }

    property QtObject _current: null
    function cleanup() {
        if (root._current) { root._current.destroy(); root._current = null; }
    }

    function _instantiate() {
        var component = Qt.createComponent(root.quickAddUrl);
        tryVerify(function () { return component.status === Component.Ready || component.status === Component.Error; }, 3000);
        compare(component.errorString(), "");
        var obj = component.createObject(root);
        verify(obj !== null);
        root._current = obj;
        return obj;
    }

    function test_closingWithUnsavedTextAsksConfirmation() {
        var qa = root._instantiate();
        qa.openPopover();
        compare(qa.open, true);
        compare(qa.confirmingDiscard, false);

        qa.summaryText = "Comprar leche";
        compare(qa.hasUnsavedText, true);

        qa.requestClose();
        // NO debe haberse cerrado directamente: pide confirmación primero.
        compare(qa.open, true, "con texto sin enviar, requestClose() no debe cerrar directamente");
        compare(qa.confirmingDiscard, true, "debe entrar en modo 'confirmar descarte'");

        // Un segundo requestClose() (equivalente a confirmar) sí cierra.
        qa.requestClose();
        compare(qa.open, false);
    }

    function test_closingWithoutTextClosesDirectly() {
        var qa = root._instantiate();
        qa.openPopover();
        compare(qa.hasUnsavedText, false);

        qa.requestClose();
        compare(qa.open, false, "sin texto sin enviar, requestClose() debe cerrar directamente");
        compare(qa.confirmingDiscard, false);
    }

    function test_forceCloseDiscardsUnsavedText() {
        var qa = root._instantiate();
        qa.openPopover();
        qa.summaryText = "algo sin enviar";
        qa.requestClose();
        compare(qa.confirmingDiscard, true);

        qa.forceClose();
        compare(qa.open, false);
        compare(qa.confirmingDiscard, false);
    }
}
