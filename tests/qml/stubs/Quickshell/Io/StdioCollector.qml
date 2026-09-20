// STUB de Quickshell.Io.StdioCollector — src/io/datastream.hpp confirma:
//   Q_PROPERTY(QString text READ text NOTIFY dataChanged);   // PROPIEDAD, no función
//   Q_PROPERTY(bool waitForEnd ...); // default true
//   signal streamFinished();
// Actions.qml lee `proc.stdout.text` (sin paréntesis) — coincide con esto.
//
// El Process stub (ver Process.qml) es quien llama a `_deliver(text)` al
// "terminar" el proceso simulado; aquí solo se guarda el valor y se emiten
// las señales reales.
import QtQml

QtObject {
    id: root
    property string text: ""
    property var data: text
    property bool waitForEnd: true

    signal streamFinished()

    function _deliver(finalText) {
        root.text = finalText || "";
        root.streamFinished();
    }
}
