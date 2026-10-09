import MoneyMatterKit
import SwiftUI
import UIKit

/// Converts between SwiftUI colours and the `#rrggbb` strings the API stores.
enum OrgColorHex {
    static func string(from color: Color) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func component(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", component(red), component(green), component(blue))
    }

    /// A pleasant default for new categories and tags.
    static let defaultHex = "#4f46e5"

    static func color(from hex: String?) -> Color {
        Color(hex: hex) ?? Color(hex: defaultHex) ?? .indigo
    }
}

/// The Fluent icon names the app can draw as SF Symbols, in the `name-20-filled` form the
/// web icon picker stores for categories and tags.
enum OrgIconCatalog {
    static let names: [String] = [
        "food", "food-pizza", "drink-coffee", "drink-wine", "cart", "shopping-bag", "receipt-bag",
        "home", "building", "key", "flash", "wrench", "toolbox", "vehicle-car", "vehicle-cab",
        "vehicle-bus", "vehicle-car-parking", "gas-pump", "airplane", "beach", "globe", "ticket",
        "heart", "pill", "stethoscope", "sport", "games", "tv", "book", "hat-graduation",
        "briefcase", "laptop", "phone", "call", "mail", "money", "money-calculator", "receipt-money",
        "receipt", "wallet", "wallet-credit-card", "building-bank", "arrow-trending", "chart-multiple",
        "calculator", "diamond", "gift", "people", "person-support", "animal-dog", "plant-grass",
        "clothes-hanger", "shield", "certificate", "gavel", "document", "pen", "puzzle-piece",
        "sparkle", "tag", "bookmark", "apps", "arrow-undo", "more-horizontal",
    ]
    .map { "\($0)-20-filled" }
    .filter { CategorySymbol.systemName(forIcon: $0) != nil }
}

/// A form row that pushes a grid of icons. `nil` means no icon.
struct OrgIconPickerLink: View {
    @Binding var selection: String?
    var tint: Color

    var body: some View {
        NavigationLink {
            OrgIconGrid(selection: $selection, tint: tint)
        } label: {
            LabeledContent("Icon") {
                if let symbol = CategorySymbol.systemName(forIcon: selection) {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                        .accessibilityLabel(Text("Selected icon"))
                } else {
                    Text("None")
                }
            }
        }
    }
}

private struct OrgIconGrid: View {
    @Binding var selection: String?
    var tint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    cell(symbol: "nosign", isSelected: selection == nil)
                }
                .accessibilityLabel(Text("No icon"))
                ForEach(OrgIconCatalog.names, id: \.self) { name in
                    if let symbol = CategorySymbol.systemName(forIcon: name) {
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            cell(symbol: symbol, isSelected: selection == name)
                        }
                        .accessibilityLabel(Text(verbatim: name.replacing(/-20-filled$/, with: "").replacing("-", with: " ")))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cell(symbol: String, isSelected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .frame(width: 52, height: 52)
            .foregroundStyle(isSelected ? .white : tint)
            .background(isSelected ? tint : Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A coloured circle with an optional Fluent icon, for tag rows.
struct OrgTagBadge: View {
    let colorHex: String?
    let icon: String?
    @ScaledMetric private var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex) ?? Color(.systemGray))
            .overlay {
                Image(systemName: CategorySymbol.systemName(forIcon: icon) ?? "tag.fill")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension AppServices {
    /// Sends `endpoint` through the live client; stubbed services have none.
    func orgCoreSend<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        guard let client else { throw APIError.network(URLError(.notConnectedToInternet)) }
        return try await client.send(endpoint)
    }
}
