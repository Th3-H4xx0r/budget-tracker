import MoneyMatterKit
import SwiftUI

extension AppServices {
    /// The live client for AI settings calls, or a "can't connect" error with stubbed services.
    func settingsAIClient() throws -> APIClient {
        guard let client else { throw APIError.network(URLError(.notConnectedToInternet)) }
        return client
    }
}

extension SettingsAIProvider {
    var settingsAIDisplayName: String {
        switch self {
        case .anthropic: String(localized: "Anthropic")
        case .openai: String(localized: "OpenAI")
        case .google: String(localized: "Google Gemini")
        case .groq: String(localized: "Groq")
        case .custom: String(localized: "Custom Endpoint")
        case .unknown: String(localized: "Other")
        }
    }

    var settingsAIKeyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .google: "AIza…"
        case .groq: "gsk_…"
        case .custom, .unknown: ""
        }
    }
}

extension SettingsAIFeature {
    /// Features with a settings card, matching the web settings page.
    static let settingsAIConfigurable: [SettingsAIFeature] = [.categorization, .statementParsing]

    var settingsAITitle: String {
        switch self {
        case .categorization: String(localized: "Categorization")
        case .statementParsing: String(localized: "Statement Parsing")
        case .investmentTransactionsParsing: String(localized: "Investment Statement Parsing")
        case .unknown: String(localized: "AI Feature")
        }
    }

    var settingsAIDescription: String {
        switch self {
        case .categorization:
            String(localized: "Suggests categories for new and imported transactions.")
        case .statementParsing:
            String(localized: "Extracts transactions from bank statements you import.")
        case .investmentTransactionsParsing:
            String(localized: "Extracts trades from brokerage statements you import.")
        case .unknown:
            ""
        }
    }

    var settingsAISymbol: String {
        switch self {
        case .categorization: "tag"
        case .statementParsing: "doc.text"
        case .investmentTransactionsParsing: "chart.line.uptrend.xyaxis"
        case .unknown: "sparkles"
        }
    }
}

extension SettingsAIModelCostTier {
    var settingsAILabel: String? {
        switch self {
        case .free: String(localized: "Free")
        case .low: String(localized: "Low cost")
        case .medium: String(localized: "Medium cost")
        case .high: String(localized: "High cost")
        case .unknown: nil
        }
    }
}

/// A red "Invalid" capsule plus the last validation error, for keys and endpoints the server
/// could no longer authenticate with.
struct SettingsAICredentialProblem: View {
    let lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            if let lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

/// A small tinted capsule, e.g. "Default" or "Your key".
struct SettingsAIBadge: View {
    let text: LocalizedStringKey
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
