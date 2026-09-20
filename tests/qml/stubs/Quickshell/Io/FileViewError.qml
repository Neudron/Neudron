// STUB del enum FileViewError (src/io/fileview.hpp). Ningún QML de
// icloud-glass compara contra estos valores por nombre (solo los reciben
// como parámetro de loadFailed/saveFailed y los registran en un log), así
// que este objeto solo existe para completitud documental de la superficie.
pragma Singleton
import QtQml

QtObject {
    readonly property int success: 0
    readonly property int unknown: 1
    readonly property int fileNotFound: 2
    readonly property int permissionDenied: 3
    readonly property int notAFile: 4
}
