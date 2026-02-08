import Foundation

/// Chyby při exportu 3D modelů
enum ExportError: Error, LocalizedError {
    case formatNotSupported(ExportFormat)
    case noData
    case conversionFailed(String)
    case fileWriteFailed(URL)
    case modelIOError(String)

    var errorDescription: String? {
        switch self {
        case .formatNotSupported(let format):
            return "Formát \(format.rawValue) není podporován"
        case .noData:
            return "Žádná data pro export"
        case .conversionFailed(let reason):
            return "Konverze selhala: \(reason)"
        case .fileWriteFailed(let url):
            return "Nepodařilo se zapsat soubor: \(url.lastPathComponent)"
        case .modelIOError(let detail):
            return "ModelIO chyba: \(detail)"
        }
    }
}
