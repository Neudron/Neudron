// STUB de Quickshell.Io.IpcHandler.
//
// Fuente de verdad: src/io/ipchandler.hpp del mirror oficial. Confirmado ahí
// (comentario Doxygen literal del propio header):
//   "Argument and return types must be explicitly specified or they will
//    not be registered."
// con un ejemplo que anota SIEMPRE el tipo de retorno, incluso ": void":
//   function setColor(color: color): void { ... }
//
// LÍMITE HONESTO de este stub (documentado también en el informe final):
// QML puro no puede reproducir en tiempo de ejecución que una función SIN
// anotación de tipo "no se registre" para IPC — esa distinción solo existe
// a nivel de QMetaObject en el motor C++ real (las funciones tipadas se
// vuelven QMetaMethod invocables por reflexión; las no tipadas son closures
// JS normales de todas formas). Este stub, por tanto, deja `target`/
// `enabled` como propiedades normales y dejar que `function foo() {}` /
// `function foo(): void {}` sean simplemente sintaxis QML común (ambas
// siguen siendo llamables directamente vía JS en este stub). La
// verificación de que TODAS las funciones de Ipc.qml llevan tipo de retorno
// explícito se hace por separado, en tests/qml/tst_ipc.qml, mediante un
// chequeo estático del propio texto fuente (ver ese archivo para el porqué).
import QtQml

QtObject {
    property bool enabled: true
    property string target: ""
}
