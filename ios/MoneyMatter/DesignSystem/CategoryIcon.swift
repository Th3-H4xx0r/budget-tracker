import MoneyMatterKit
import SwiftUI
import UIKit

/// Maps the web app's Fluent icon names (e.g. `food-20-filled`) to SF Symbols.
enum CategorySymbol {
    static func systemName(forIcon icon: String?) -> String? {
        guard let icon, !icon.isEmpty else { return nil }
        if let cached = resolved[icon] { return cached }
        let base = icon.replacing(/-\d+-(filled|regular)$/, with: "")
        // A symbol missing from the running OS falls back to the category initial.
        let name = table[base].flatMap { UIImage(systemName: $0) == nil ? nil : $0 }
        resolved[icon] = .some(name)
        return name
    }

    /// Lookups already made, since every transaction row asks.
    private static var resolved: [String: String?] = [:]

    private static let table: [String: String] = [
        "airplane": "airplane",
        "animal-dog": "dog.fill",
        "apps": "square.grid.2x2.fill",
        "arrow-trending": "chart.line.uptrend.xyaxis",
        "arrow-undo": "arrow.uturn.backward",
        "beach": "beach.umbrella.fill",
        "book": "book.fill",
        "bookmark": "bookmark.fill",
        "briefcase": "briefcase.fill",
        "building": "building.2.fill",
        "building-bank": "building.columns.fill",
        "calculator": "plusminus",
        "call": "phone.fill",
        "cart": "cart.fill",
        "certificate": "rosette",
        "chart-multiple": "chart.bar.fill",
        "clothes-hanger": "tshirt.fill",
        "diamond": "diamond.fill",
        "document": "doc.fill",
        "drink-coffee": "cup.and.saucer.fill",
        "drink-wine": "wineglass.fill",
        "flash": "bolt.fill",
        "food": "fork.knife",
        "food-pizza": "takeoutbag.and.cup.and.straw.fill",
        "games": "gamecontroller.fill",
        "gas-pump": "fuelpump.fill",
        "gavel": "hammer.fill",
        "gift": "gift.fill",
        "globe": "globe",
        "handshake": "hand.thumbsup.fill",
        "hat-graduation": "graduationcap.fill",
        "heart": "heart.fill",
        "home": "house.fill",
        "key": "key.fill",
        "laptop": "laptopcomputer",
        "mail": "envelope.fill",
        "money": "banknote.fill",
        "money-calculator": "dollarsign.circle.fill",
        "more-horizontal": "ellipsis",
        "pen": "pencil",
        "people": "person.2.fill",
        "person-support": "person.fill.questionmark",
        "phone": "iphone",
        "pill": "pills.fill",
        "plant-grass": "leaf.fill",
        "puzzle-piece": "puzzlepiece.fill",
        "receipt": "doc.plaintext.fill",
        "receipt-bag": "bag.fill",
        "receipt-money": "banknote",
        "shield": "shield.fill",
        "shopping-bag": "bag.fill",
        "sparkle": "sparkles",
        "sport": "figure.run",
        "stethoscope": "stethoscope",
        "tag": "tag.fill",
        "ticket": "ticket.fill",
        "toolbox": "wrench.and.screwdriver.fill",
        "tv": "tv.fill",
        "vehicle-bus": "bus.fill",
        "vehicle-cab": "car.fill",
        "vehicle-car": "car.fill",
        "vehicle-car-parking": "parkingsign.circle.fill",
        "wallet": "wallet.pass.fill",
        "wallet-credit-card": "creditcard.fill",
        "wrench": "wrench.fill",
    ]
}

/// A filled circle in the category colour with its symbol, or its initial when the icon
/// has no SF Symbol. Transfers get a neutral arrows badge.
struct CategoryIcon: View {
    private let colorHex: String?
    private let symbol: String?
    private let initial: String
    @ScaledMetric private var size: CGFloat

    init(category: Category?, isTransfer: Bool = false, size: CGFloat = 36) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        if isTransfer, category == nil {
            colorHex = nil
            symbol = "arrow.left.arrow.right"
            initial = ""
        } else {
            colorHex = category?.color
            symbol = CategorySymbol.systemName(forIcon: category?.icon)
            initial = category?.name.first.map { String($0).uppercased() } ?? "?"
        }
    }

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex) ?? Color(.systemGray))
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.44, weight: .semibold))
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
