import QtQuick
import QtTest
import Quickshell as QS
import "../../quickshell/.config/quickshell/icloud-glass" as Root

TestCase {
    id: root
    name: "DebugView"

    function _cachePath(name) {
        return Qt.resolvedUrl("./.tmp/" + name).toString().replace("file://", "");
    }

    function test_instantiatesWithoutErrors() {
        QS.Quickshell._setTestEnv({
            "HOME": "/nonexistent-home-for-tests",
            "ICLOUD_GLASS_CACHE_DIR": root._cachePath("cache-ok")
        });
        var component = Qt.createComponent(Qt.resolvedUrl("../../quickshell/.config/quickshell/icloud-glass/DebugView.qml"));
        tryVerify(function () { return component.status === Component.Ready || component.status === Component.Error; }, 3000);
        compare(component.errorString(), "");
        var obj = component.createObject(null);
        verify(obj !== null);
        // Esta vez NO destruimos hasta que TODA la carga async haya
        // terminado de verdad (ready===true), para descartar que el fallo
        // sea solo un artefacto de destruir el objeto demasiado pronto.
        tryVerify(function () { return obj.buildDump().indexOf("ready: true") !== -1; }, 3000);
        wait(200);
        console.log("FINAL DUMP:\n" + obj.buildDump());
        obj.destroy();
    }
}
