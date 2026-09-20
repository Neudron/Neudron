// STUB de Quickshell.Io.Process para el arnés offscreen.
//
// Fuente de verdad: src/io/process.hpp del mirror oficial. Confirmado ahí:
//   Q_PROPERTY(QList<QString> command ...)              -> list<string>
//   Q_PROPERTY(bool running ...)                          -> arranca/mata
//   signal started()
//   signal exited(qint32 exitCode, QProcess::ExitStatus exitStatus)
//   Q_PROPERTY(DataStreamParser* stdout ...) / stderr
// Todo eso coincide con cómo lo usa Actions.qml (proc.command = [...],
// proc.exited.connect(function(exitCode, exitStatus) {...}),
// proc.stdout.text / proc.stderr.text, proc.running = true).
//
// Este stub deliberadamente NO EJECUTA NADA (requisito del encargo): en vez
// de lanzar QProcess, registra la invocación en Quickshell.Io.ProcessRegistry
// (ver ese archivo) para que los tests puedan afirmar exactamente qué
// comando se habría ejecutado, y complete de forma asíncrona con el
// resultado que el test haya configurado (por defecto, éxito silencioso).
import QtQml

QtObject {
    id: root

    property bool running: false
    readonly property var processId: root.running ? 424242 : null
    property var command: []
    property string workingDirectory: ""
    property var environment: ({})
    property bool clearEnvironment: false
    property QtObject stdout: null
    property QtObject stderr: null
    property bool stdinEnabled: false

    signal started()
    signal exited(int exitCode, var exitStatus)

    // Nota: la API real también expone signal(int) y write(string), pero
    // ningún QML de icloud-glass los usa hoy, así que este stub no los
    // implementa (evita declarar una función llamada "signal", palabra
    // reservada en QML para declarar señales).
    function write(data) {}
    function startDetached() {
        root._recordCall();
    }

    onRunningChanged: {
        if (root.running) {
            root._recordCall();
            Qt.callLater(root._finish);
        }
    }

    function _recordCall() {
        ProcessRegistry.record({
            command: (root.command || []).slice(),
            workingDirectory: root.workingDirectory,
            environment: root.environment,
            clearEnvironment: root.clearEnvironment
        });
        root.started();
    }

    function _finish() {
        if (!root.running) return; // ya se marcó running=false desde fuera (signal/kill)
        var result = ProcessRegistry.resultFor(root.command || []);
        root.running = false;
        if (root.stdout && root.stdout._deliver) root.stdout._deliver(result.stdout || "");
        if (root.stderr && root.stderr._deliver) root.stderr._deliver(result.stderr || "");
        var code = result.exitCode !== undefined ? result.exitCode : 0;
        root.exited(code, code === 0 ? 0 : 1);
    }
}
