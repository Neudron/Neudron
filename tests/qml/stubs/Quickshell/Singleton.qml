// STUB de Quickshell.Singleton — src/core/singleton.hpp confirma que es solo
// `ReloadPropagator` (alias QML "Scope") sin propiedades propias: un
// contenedor cuyo default property es `children: list<QObject>` (heredado
// de ReloadPropagator, src/core/reload.hpp). Todos los singletons de
// icloud-glass (Config, DataStore, Actions, Ipc) declaran `pragma Singleton`
// + `Singleton { ... }` como raíz y cuelgan Timer/FileView/Loader/
// IpcHandler como hijos directos, confiando en ese default property.
import QtQml

QtObject {
    default property list<QtObject> children
}
