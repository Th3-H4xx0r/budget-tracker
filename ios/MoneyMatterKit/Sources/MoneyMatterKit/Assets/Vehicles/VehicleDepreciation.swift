import Foundation

/// One point on the vehicle value curve.
public struct VehicleDepreciationPoint: Sendable, Hashable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// The depreciation model, mirroring the backend's `computeVehicleValue` so the chart
/// agrees with the headline value: compound annual depreciation walked year by year from
/// the anchor, the partial final year prorated by elapsed days, floored at salvage.
public enum VehicleDepreciation {
    /// Annual rates (percent) by year since purchase, per class. Past the end of a curve
    /// `tailRatePct` applies. Kept identical to `CLASS_DEFAULT_CURVES` in the shared package.
    public static let classDefaultCurves: [VehicleClass: [Double]] = [
        .sedan: [20, 15, 12, 10, 8, 7, 6, 5, 5, 4],
        .suv: [18, 14, 11, 10, 8, 7, 6, 5, 5, 4],
        .truck: [15, 12, 10, 9, 8, 7, 6, 5, 5, 4],
        .luxury: [25, 18, 14, 12, 10, 8, 7, 6, 5, 5],
        .ev: [22, 17, 13, 10, 8, 7, 6, 5, 5, 4],
        .motorcycle: [20, 15, 12, 10, 8, 7, 6, 5, 5, 4],
        .other: [20, 15, 12, 10, 8, 7, 6, 5, 5, 4],
    ]

    public static let tailRatePct: Double = 4

    /// The rate for one year as a fraction, e.g. `0.2`.
    public static func annualRate(
        vehicleClass: VehicleClass,
        preset: VehicleDepreciationPreset,
        customAnnualRatePct: Double?,
        yearIndex: Int
    ) -> Double {
        if preset == .custom { return (customAnnualRatePct ?? 0) / 100 }
        let curve = classDefaultCurves[vehicleClass] ?? classDefaultCurves[.other] ?? []
        let basePct = yearIndex < curve.count ? curve[yearIndex] : tailRatePct
        let multiplier: Double = switch preset {
        case .slow: 0.7
        case .fast: 1.3
        default: 1.0
        }
        return basePct * multiplier / 100
    }

    /// The value at `asOf`, starting from `anchorValue` on `anchorDate`.
    public static func value(
        anchorValue: Double,
        anchorDate: Date,
        asOf: Date,
        vehicleClass: VehicleClass,
        preset: VehicleDepreciationPreset,
        customAnnualRatePct: Double?,
        floor: Double,
        calendar: Calendar = .current
    ) -> Double {
        guard days(from: anchorDate, to: asOf, calendar: calendar) > 0 else { return anchorValue }
        var value = anchorValue
        var cursor = anchorDate
        var yearIndex = 0
        while true {
            guard let nextAnniversary = calendar.date(byAdding: .year, value: 1, to: cursor) else { return value }
            let rate = annualRate(
                vehicleClass: vehicleClass,
                preset: preset,
                customAnnualRatePct: customAnnualRatePct,
                yearIndex: yearIndex
            )
            if asOf >= nextAnniversary {
                value *= 1 - rate
                if value < floor { return floor }
                cursor = nextAnniversary
                yearIndex += 1
                continue
            }
            let daysInYear = days(from: cursor, to: nextAnniversary, calendar: calendar)
            let partialDays = days(from: cursor, to: asOf, calendar: calendar)
            if partialDays > 0, daysInYear > 0 {
                value *= 1 - rate * Double(partialDays) / Double(daysInYear)
                if value < floor { return floor }
            }
            return value
        }
    }

    /// The value curve sampled monthly from purchase, projected `monthsHorizon` past the
    /// latest anchor. An override after purchase splits it in two, joined by a vertical
    /// step at the override date. The salvage floor is a share of the purchase price, so it
    /// stays put across overrides.
    public static func timeline(
        purchaseValue: Double,
        purchaseDate: Date,
        override: VehicleDepreciationPoint?,
        vehicleClass: VehicleClass,
        preset: VehicleDepreciationPreset,
        customAnnualRatePct: Double?,
        salvageFloorPct: Double,
        monthsHorizon: Int,
        calendar: Calendar = .current
    ) -> [VehicleDepreciationPoint] {
        let floor = purchaseValue * salvageFloorPct / 100
        func segment(anchorValue: Double, anchorDate: Date, endDate: Date) -> [VehicleDepreciationPoint] {
            var points = [VehicleDepreciationPoint(date: anchorDate, value: anchorValue)]
            var month = 1
            while let date = calendar.date(byAdding: .month, value: month, to: anchorDate), date <= endDate {
                let value = value(
                    anchorValue: anchorValue,
                    anchorDate: anchorDate,
                    asOf: date,
                    vehicleClass: vehicleClass,
                    preset: preset,
                    customAnnualRatePct: customAnnualRatePct,
                    floor: floor,
                    calendar: calendar
                )
                points.append(VehicleDepreciationPoint(date: date, value: value))
                month += 1
            }
            return points
        }

        guard let override, override.date > purchaseDate else {
            let end = calendar.date(byAdding: .month, value: monthsHorizon, to: purchaseDate) ?? purchaseDate
            return segment(anchorValue: purchaseValue, anchorDate: purchaseDate, endDate: end)
        }

        let before = segment(anchorValue: purchaseValue, anchorDate: purchaseDate, endDate: override.date)
        let last = before[before.count - 1]
        let step: [VehicleDepreciationPoint] = last.date == override.date
            ? [override]
            : [VehicleDepreciationPoint(date: override.date, value: last.value), override]
        let end = calendar.date(byAdding: .month, value: monthsHorizon, to: override.date) ?? override.date
        let after = segment(anchorValue: override.value, anchorDate: override.date, endDate: end)
        return before + step + after.dropFirst()
    }

    /// The first timeline value on or after `date`, or the last one.
    public static func projectedValue(in timeline: [VehicleDepreciationPoint], at date: Date) -> Double {
        timeline.first { $0.date >= date }?.value ?? timeline.last?.value ?? 0
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
