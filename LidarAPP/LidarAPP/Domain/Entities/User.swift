import Foundation

/// Represents an authenticated user
struct User: Identifiable, Codable, Sendable {
    let id: String
    let email: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date
    let subscription: SubscriptionTier
    let scanCredits: Int
    let preferences: UserPreferences

    init(
        id: String,
        email: String,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        createdAt: Date = Date(),
        subscription: SubscriptionTier = .free,
        scanCredits: Int = 5,
        preferences: UserPreferences = UserPreferences()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.subscription = subscription
        self.scanCredits = scanCredits
        self.preferences = preferences
    }

    var name: String {
        displayName ?? email.components(separatedBy: "@").first ?? "User"
    }

    var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Subscription

enum SubscriptionTier: String, Codable, CaseIterable, Sendable {
    case free
    case pro
    case enterprise

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .enterprise: return "Enterprise"
        }
    }

    var monthlyScans: Int {
        switch self {
        case .free: return 5
        case .pro: return 50
        case .enterprise: return .max
        }
    }

    var maxResolution: String {
        switch self {
        case .free: return "Standard"
        case .pro: return "High"
        case .enterprise: return "Ultra"
        }
    }

    var features: [String] {
        switch self {
        case .free:
            return [
                "5 scans/month",
                "Standard resolution",
                "Basic export (OBJ)",
                "7-day cloud storage"
            ]
        case .pro:
            return [
                "50 scans/month",
                "High resolution",
                "All export formats",
                "30-day cloud storage",
                "Priority processing",
                "Offline measurements"
            ]
        case .enterprise:
            return [
                "Unlimited scans",
                "Ultra resolution",
                "All export formats",
                "Unlimited storage",
                "Priority processing",
                "API access",
                "Custom branding",
                "Dedicated support"
            ]
        }
    }
}

// MARK: - User Preferences

struct UserPreferences: Codable, Sendable {
    var measurementUnit: MeasurementUnit = .meters
    var autoUpload: Bool = true
    var hapticFeedback: Bool = true
    var showTutorials: Bool = true
    var defaultExportFormat: ExportFormat = .usdz
    var scanQuality: ScanQualityPreference = .balanced

    enum ScanQualityPreference: String, Codable, CaseIterable, Sendable {
        case fast
        case balanced
        case quality

        var displayName: String {
            switch self {
            case .fast: return "Fast"
            case .balanced: return "Balanced"
            case .quality: return "High Quality"
            }
        }
    }

    enum ExportFormat: String, Codable, CaseIterable, Sendable {
        case usdz
        case gltf
        case obj
        case ply

        var displayName: String {
            rawValue.uppercased()
        }
    }
}

// MARK: - Auth Tokens

struct AuthTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var needsRefresh: Bool {
        // Refresh if less than 5 minutes remaining
        Date().addingTimeInterval(300) >= expiresAt
    }
}

// MARK: - Auth Credentials

struct LoginCredentials: Sendable {
    let email: String
    let password: String
}

struct RegisterCredentials: Sendable {
    let email: String
    let password: String
    let displayName: String?
}

// MARK: - API Response Models

struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

struct TokenRefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}
