import SwiftUI
import UIKit

/// Design tokens in the IntelliStock language: Apple Stocks with one violet accent.
/// Surfaces and text use the system's semantic colours directly; this file names only
/// what the system does not.
///
/// No gradients, shadows or card borders anywhere. Charts fill their area with a flat
/// `DS.chartAreaOpacity` tint of the line colour.
nonisolated enum DS {
    /// One colour, one meaning. All adapt to light and dark.
    enum Palette {
        /// `AccentColor`: #6D28D9 light, #A78BFA dark. The only brand colour.
        static let accent = Color.accentColor
        static let success = Color.green
        static let danger = Color.red
        static let warning = Color.orange
        static let info = Color.blue
        static let teal = Color.teal
        /// Income, gains and positive changes.
        static let up = Color.green
        /// Losses and negative changes. Plain expense amounts in lists stay `.primary`.
        static let down = Color.red
        /// Text and glyphs on an accent fill. White on the light accent #6D28D9 (7.1:1);
        /// near-black #04040C on the dark accent #A78BFA, where white is only 2.7:1.
        static let onAccent = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 4 / 255, green: 4 / 255, blue: 12 / 255, alpha: 1)
                : .white
        })

        /// A status colour made legible as text on its own 15 % tint: darkened by 40 %
        /// towards black in light mode (system green or orange on a pale tint is about
        /// 2:1), unchanged in dark mode, where it already passes.
        static func onTint(_ color: Color, in scheme: ColorScheme) -> Color {
            scheme == .dark ? color : color.mix(with: .black, by: 0.4)
        }
    }

    /// The grouped background family.
    enum Surface {
        /// The screen background.
        static let canvas = Color(uiColor: .systemGroupedBackground)
        /// Cards and grouped rows.
        static let panel = Color(uiColor: .secondarySystemGroupedBackground)
        /// Insets inside a panel (inputs, wells).
        static let inset = Color(uiColor: .tertiarySystemGroupedBackground)
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    /// Corner radii, always drawn `.continuous`.
    enum Radius {
        static let card: CGFloat = 22
        static let control: CGFloat = 12
        static let small: CGFloat = 8
        /// Icon tiles round 30 % of their side.
        static let iconTileFraction: CGFloat = 0.3
        /// Settings tiles round 24 % of their side, as in iOS Settings.
        static let settingsTileFraction: CGFloat = 0.24
    }

    enum Opacity {
        /// A status colour behind status text (badges, icon tiles, error rows).
        static let tintFill: Double = 0.15
        /// The flat area fill under a chart line.
        static let chartArea: Double = 0.12
    }

    /// Shorthand for `Opacity.tintFill`.
    static let tintFill: Double = Opacity.tintFill
    /// Shorthand for `Opacity.chartArea`.
    static let chartAreaOpacity: Double = Opacity.chartArea
    /// Padding inside a `DSCard`.
    static let cardPadding: CGFloat = 16
    /// Space between groups inside a `DSCard`.
    static let cardGroupSpacing: CGFloat = 12
    /// The dash of a chart's baseline rule: Stocks' dotted start-value line.
    static let baselineDash: [CGFloat] = [2, 3]
}

extension View {
    /// The hero figure: 40 pt bold, scaled relative to `.largeTitle`, with monospaced digits.
    func dsValueHero() -> some View {
        modifier(ValueHeroStyle())
    }

    /// The primary action: `.borderedProminent` in the accent with `onAccent` labels.
    func dsProminentButton() -> some View {
        buttonStyle(.borderedProminent)
            .foregroundStyle(DS.Palette.onAccent)
    }

    /// A floating primary action: Liquid Glass `.glassProminent` with `onAccent` labels.
    func dsGlassProminentButton() -> some View {
        buttonStyle(.glassProminent)
            .foregroundStyle(DS.Palette.onAccent)
    }
}

private struct ValueHeroStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
    }
}

/// The violet ramps for donuts and allocation charts, from IntelliStock's sector palette,
/// flattened to one solid colour per segment.
///
/// Segments are ranked largest first: rank 0 is the strongest violet, and smaller segments
/// fade. In light mode emphasis means stronger (towards #6D28D9); in dark mode it means
/// brighter (towards lavender).
///
///     let colors = DonutPalette.colors(count: slices.count, scheme: colorScheme)
nonisolated enum DonutPalette {
    /// One ramp, from brightness 0 (least emphasis) to 1 (most).
    struct Ramp: Equatable, Sendable {
        let deep: UInt32
        let bright: UInt32

        func color(at brightness: Double) -> Color {
            DonutPalette.lerp(deep, bright, brightness)
        }
    }

    /// Dark mode: hi #7C5CE6→#EBE0FF, mid #4A2C9E→#B79BFF, lo #24114F→#7E55E6.
    static let dark = (hi: Ramp(deep: 0x7C5CE6, bright: 0xEBE0FF),
                       mid: Ramp(deep: 0x4A2C9E, bright: 0xB79BFF),
                       lo: Ramp(deep: 0x24114F, bright: 0x7E55E6))

    /// Light mode: hi #D8CCFB→#8B5CF6, mid #B9A5F7→#6D28D9, lo #8E73E0→#4C1D95.
    static let light = (hi: Ramp(deep: 0xD8CCFB, bright: 0x8B5CF6),
                        mid: Ramp(deep: 0xB9A5F7, bright: 0x6D28D9),
                        lo: Ramp(deep: 0x8E73E0, bright: 0x4C1D95))

    /// The colour of the segment at `rank` (0 = largest) out of `count`.
    static func color(rank: Int, count: Int, scheme: ColorScheme) -> Color {
        let ramps = scheme == .dark ? dark : light
        let brightness = count <= 1 ? 1 : 1 - Double(min(max(rank, 0), count - 1)) / Double(count - 1)
        // The face colour IntelliStock uses for a top face: hi blended 35 % towards mid.
        let hi = rgb(ramps.hi.deep, ramps.hi.bright, brightness)
        let mid = rgb(ramps.mid.deep, ramps.mid.bright, brightness)
        return Color(
            .sRGB,
            red: hi.r + (mid.r - hi.r) * 0.35,
            green: hi.g + (mid.g - hi.g) * 0.35,
            blue: hi.b + (mid.b - hi.b) * 0.35
        )
    }

    /// `count` colours, largest segment first.
    static func colors(count: Int, scheme: ColorScheme) -> [Color] {
        (0..<max(count, 0)).map { color(rank: $0, count: count, scheme: scheme) }
    }

    fileprivate static func lerp(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        let c = rgb(a, b, t)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    private static func rgb(_ a: UInt32, _ b: UInt32, _ t: Double) -> (r: Double, g: Double, b: Double) {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) / 255 }
        let t = min(max(t, 0), 1)
        return (
            channel(a, 16) + (channel(b, 16) - channel(a, 16)) * t,
            channel(a, 8) + (channel(b, 8) - channel(a, 8)) * t,
            channel(a, 0) + (channel(b, 0) - channel(a, 0)) * t
        )
    }
}
