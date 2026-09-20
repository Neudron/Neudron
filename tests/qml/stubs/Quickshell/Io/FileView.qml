// STUB de Quickshell.Io.FileView para el arnés de tests offscreen (tests/qml).
//
// Fuente de verdad para esta API: src/io/fileview.hpp del mirror oficial
// (https://github.com/quickshell-mirror/quickshell, ref usada:
// tests/qml/stubs/VERSIONS.md). Puntos verificados contra ese header:
//   - `text()` y `data()` son Q_INVOKABLE (funciones), NO propiedades. Por
//     eso el código de producción las llama como `text()` — es correcto.
//   - Señales: loaded(), loadFailed(FileViewError error), saved(),
//     saveFailed(FileViewError error), fileChanged(), adapterUpdated().
//   - Propiedades usadas por el código de producción: path, watchChanges.
//     (blockLoading/blockAllReads/adapter/atomicWrites/etc. existen en la
//     API real pero ningún QML de icloud-glass las usa, así que este stub
//     las declara para completitud de la superficie pero no les da semántica
//     rica.)
//
// Simplificación deliberada (documentada, no oculta): la vigilancia de
// cambios en disco de verdad usa inotify vía Qt; QML puro no tiene ese
// primitivo. Este stub la sustituye por un Timer de sondeo de intervalo
// corto (ver `pollIntervalMs`) SOLO mientras `watchChanges` es true. Es
// suficiente para que los tests (que reescriben los fixtures y esperan con
// tryVerify) vean fileChanged(), pero NO reproduce inotify de verdad.
//
// Lee del disco de VERDAD (no simula contenido): usa XMLHttpRequest sobre
// file://, que en este contenedor requiere QML_XHR_ALLOW_FILE_READ=1
// (lo fija tests/run.sh).

import QtQml

QtObject {
    id: root

    property string path: ""
    property bool preload: true
    property bool blockLoading: false
    property bool blockAllReads: false
    property bool blockWrites: false
    property bool atomicWrites: true
    property bool printErrors: true
    property bool watchChanges: false
    property var adapter: null
    // NOTA: la API real tiene TANTO una propiedad `loaded` (bool) COMO una
    // señal `loaded()` — válido en Qt/C++ (su NOTIFY es loadedOrAsyncChanged,
    // no loadedChanged), pero QML puro no permite una propiedad y una señal
    // con el mismo nombre en el mismo tipo (colisión: `root.loaded` no puede
    // resolver a la vez a un booleano y a una función invocable — probado
    // empíricamente: producía "TypeError: Type error" al emitir la señal).
    // Como ningún QML de icloud-glass lee la PROPIEDAD `loaded` (solo usan
    // la señal vía onLoaded/onFileChanged), este stub renuncia a exponerla
    // como propiedad pública y solo guarda el estado internamente en
    // `_loaded` (más abajo).

    property int pollIntervalMs: 40

    property bool _loaded: false
    property string _text: ""
    // `var` (no `string`): empieza en `undefined` para distinguir "nunca
    // cargado" de "cargado con contenido vacío"; un `string` no admite
    // `undefined` como valor inicial.
    property var _lastKnownContent: undefined

    signal loaded()
    signal loadFailed(var error)
    signal saved()
    signal saveFailed(var error)
    signal fileChanged()
    signal adapterUpdated()

    function text() {
        return root._text;
    }

    function data() {
        // No se usa en icloud-glass; se deja como no-op consistente con la
        // API real (devolvería un ArrayBuffer).
        return root._text;
    }

    function reload() {
        root._load(true);
    }

    function setText(newText) {
        // No usado por icloud-glass hoy, pero se implementa de forma honesta
        // para no dejar una trampa silenciosa: escribe de verdad si algún
        // futuro código lo necesitara. No hace fsync ni escritura atómica
        // real (a diferencia de la API real). Se usa PUT asíncrono a
        // propósito: probado empíricamente en este arnés que el PUT SÍNCRONO
        // sobre archivo local no refleja el contenido de forma fiable en una
        // lectura inmediata posterior (aunque el archivo queda bien escrito
        // al terminar el proceso) — es una limitación del backend de XHR de
        // Qt para file://, no de icloud-glass.
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200 || xhr.status === 0) {
                root._text = newText;
                root._lastKnownContent = newText;
                root.saved();
            } else {
                root.saveFailed(1 /* FileViewError.Unknown */);
            }
        };
        xhr.open("PUT", root._fileUrl(), true);
        xhr.send(newText);
    }

    function writeAdapter() {}
    function waitForJob() { return true; }

    function _fileUrl() {
        if (root.path.length === 0) return "";
        if (root.path.indexOf("file://") === 0) return root.path;
        return "file://" + root.path;
    }

    function _load(isReload) {
        if (root.path.length === 0) {
            root._loaded = false;
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                var wasLoaded = root._loaded;
                root._text = xhr.responseText;
                root._lastKnownContent = xhr.responseText;
                root._loaded = true;
                if (isReload && wasLoaded) {
                    root.fileChanged();
                } else {
                    root.loaded();
                }
            } else {
                if (root.printErrors)
                    console.warn("FileView stub: no se pudo cargar " + root.path + " (status " + xhr.status + ")");
                root.loadFailed(2 /* FileViewError.FileNotFound (aproximado) */);
            }
        };
        xhr.open("GET", root._fileUrl(), true);
        xhr.send();
    }

    onPathChanged: {
        pollTimer.stop();
        if (root.preload && root.path.length > 0) {
            root._load(false);
        }
        if (root.watchChanges && root.path.length > 0) {
            pollTimer.start();
        }
    }

    onWatchChangesChanged: {
        if (root.watchChanges && root.path.length > 0) {
            pollTimer.start();
        } else {
            pollTimer.stop();
        }
    }

    property QtObject pollTimer: Timer {
        interval: root.pollIntervalMs
        repeat: true
        running: false
        onTriggered: root._checkForChanges()
    }

    function _checkForChanges() {
        if (root.path.length === 0) return;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) return;
            if (xhr.responseText !== root._lastKnownContent) {
                root._text = xhr.responseText;
                root._lastKnownContent = xhr.responseText;
                root._loaded = true;
                root.fileChanged();
            }
        };
        xhr.open("GET", root._fileUrl(), true);
        xhr.send();
    }

    // Nota: NO hay Component.onCompleted que repita la carga inicial. En QML,
    // asignar `path`/`watchChanges` como valores declarativos ya dispara
    // onPathChanged/onWatchChangesChanged durante la construcción (difieren
    // de sus valores por defecto ""/false), así que ese único disparo basta;
    // añadir una carga extra en onCompleted duplicaría loaded() la primera vez.
}
