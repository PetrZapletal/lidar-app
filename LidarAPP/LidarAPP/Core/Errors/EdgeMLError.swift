import Foundation

/// Errors for on-device ML processing pipeline
enum EdgeMLError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case predictionFailed(String)
    case invalidInput(String)
    case processingFailed(String)
    case insufficientData
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "ML model is not loaded"
        case .modelLoadFailed(let detail):
            return "Failed to load ML model: \(detail)"
        case .predictionFailed(let detail):
            return "ML prediction failed: \(detail)"
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        case .processingFailed(let detail):
            return "Processing failed: \(detail)"
        case .insufficientData:
            return "Insufficient data for processing"
        case .cancelled:
            return "ML processing was cancelled"
        }
    }
}
