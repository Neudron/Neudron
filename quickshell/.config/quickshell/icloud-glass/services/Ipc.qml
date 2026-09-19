pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ipc: expone el panel a línea de comandos vía IpcHandler (target "panel").
// Comandos de ejemplo, ejecutables desde fuera de Quickshell:
//
//   qs -c icloud-glass ipc call panel toggle   -> alterna abierto/cerrado
//   qs -c icloud-glass ipc call panel open     -> fuerza apertura
//   qs -c icloud-glass ipc call panel close    -> fuerza cierre
//   qs -c icloud-glass ipc call panel refresh  -> fuerza sync (Actions.sync())
//
// `shell.qml` (del orquestador) debe enlazar su visibilidad a `Ipc.panelOpen`
// y, opcionalmente, escuchar `panelOpened()`/`panelClosed()` para animaciones
// de entrada/salida.
Singleton {
    id: root

    // Estado del panel, pensado para que shell.qml haga:
    //   visible: Ipc.panelOpen
    // (o lo use para disparar una animación de aparición/desaparición).
    property bool panelOpen: false

    signal panelOpened()
    signal panelClosed()
    signal refreshRequested()

    IpcHandler {
        target: "panel"

        function toggle() {
            root.panelOpen = !root.panelOpen;
            if (root.panelOpen) root.panelOpened();
            else root.panelClosed();
        }

        function open() {
            if (root.panelOpen) return;
            root.panelOpen = true;
            root.panelOpened();
        }

        function close() {
            if (!root.panelOpen) return;
            root.panelOpen = false;
            root.panelClosed();
        }

        // Solo emite la señal: `shell.qml` es quien llama a Actions.sync().
        // Llamar a `Actions` desde aquí obligaría a que este singleton importe el
        // qmldir de su propio directorio, lo que crea una dependencia circular
        // entre singletons hermanos. Emitir y delegar mantiene Ipc sin dependencias.
        function refresh() {
            root.refreshRequested();
        }
    }
}
