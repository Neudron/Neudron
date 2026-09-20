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

        // NOTA (D1, tests/qml/tst_ipc.qml): las 4 funciones de abajo llevan
        // anotación explícita de tipo de retorno (`: void`) porque
        // src/io/ipchandler.hpp del mirror oficial de Quickshell 0.3.x es
        // taxativo: "Argument and return types must be explicitly specified
        // or they will not be registered." Sin el `: void`, Quickshell real
        // NO las habría registrado para IPC y `qs ipc call panel toggle`
        // (documentado más arriba en este mismo archivo) habría fallado en
        // silencio. El comportamiento de negocio (togglear panelOpen, abrir/
        // cerrar de forma idempotente, reenviar refresh) ya estaba bien y no
        // ha cambiado.
        function toggle(): void {
            root.panelOpen = !root.panelOpen;
            if (root.panelOpen) root.panelOpened();
            else root.panelClosed();
        }

        function open(): void {
            if (root.panelOpen) return;
            root.panelOpen = true;
            root.panelOpened();
        }

        function close(): void {
            if (!root.panelOpen) return;
            root.panelOpen = false;
            root.panelClosed();
        }

        // Solo emite la señal: `shell.qml` es quien llama a Actions.sync().
        // Llamar a `Actions` desde aquí obligaría a que este singleton importe el
        // qmldir de su propio directorio, lo que crea una dependencia circular
        // entre singletons hermanos. Emitir y delegar mantiene Ipc sin dependencias.
        function refresh(): void {
            root.refreshRequested();
        }
    }
}
