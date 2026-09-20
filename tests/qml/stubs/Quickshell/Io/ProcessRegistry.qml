// ProcessRegistry — NO es parte de la API real de Quickshell. Es el punto de
// introspección que exige el encargo: "Process stub: NO ejecuta nada;
// registra el comando en una lista global accesible desde los tests."
//
// Uso desde un test:
//   import Quickshell.Io as Io
//   ...
//   Io.ProcessRegistry.reset();
//   ...(disparar la acción)...
//   compare(Io.ProcessRegistry.calls[0].command,
//           ["icloud-glass-write", "todo-done", "some-uid"]);
//
// Por defecto cada comando "sale" con código 0 y stdout/stderr vacíos, de
// forma asíncrona (Qt.callLater, para imitar que un proceso real no termina
// en el mismo tick en el que se lanza). Un test puede fijar un resultado
// distinto ANTES de disparar la acción con setResult(prefijo, resultado).
pragma Singleton
import QtQml

QtObject {
    id: root

    property var calls: []
    property var _overrides: []

    readonly property var lastCall: calls.length > 0 ? calls[calls.length - 1] : null

    function reset() {
        calls = [];
        _overrides = [];
    }

    // prefix: array de strings que debe calzar al principio de command.
    // result: { exitCode: int, stdout: string, stderr: string }
    function setResult(prefix, result) {
        _overrides = _overrides.concat([{ prefix: prefix, result: result }]);
    }

    function record(entry) {
        calls = calls.concat([entry]);
    }

    function resultFor(command) {
        var best = null;
        var bestLen = -1;
        for (var i = 0; i < _overrides.length; i++) {
            var o = _overrides[i];
            if (_isPrefix(o.prefix, command) && o.prefix.length > bestLen) {
                best = o.result;
                bestLen = o.prefix.length;
            }
        }
        if (best) return best;
        return { exitCode: 0, stdout: "", stderr: "" };
    }

    function _isPrefix(prefix, command) {
        if (prefix.length > command.length) return false;
        for (var i = 0; i < prefix.length; i++) {
            if (prefix[i] !== command[i]) return false;
        }
        return true;
    }
}
