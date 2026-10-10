import Foundation
import MoneyMatterKit

/// The span Home's spending cards cover. Each case resolves to an inclusive day range capped
/// at today and the matching earlier range the hero compares against.
enum HomePeriod: Hashable {
    case month(year: Int, month: Int)
    case ytd
    /// "1Y": twelve whole calendar months ending with the current one.
    case last12Months
    case lastYear
    /// Any whole calendar year before last year.
    case year(Int)

    /// The segments of the period picker. A specific earlier year has no segment.
    enum Kind: Hashable, CaseIterable, Identifiable {
        case month, ytd, last12Months, lastYear

        var id: Self { self }

        var label: String {
            switch self {
            case .month: String(localized: "Month")
            case .ytd: String(localized: "YTD")
            case .last12Months: String(localized: "1Y")
            case .lastYear: String(localized: "Last year")
            }
        }
    }

    /// Inclusive on both ends.
    struct DayRange: Hashable {
        let from: CalendarDate
        let to: CalendarDate
    }

    static func currentMonth(today: CalendarDate = CalendarDate(date: .now)) -> HomePeriod {
        .month(year: today.year, month: today.month)
    }

    static func defaultPeriod(for kind: Kind, today: CalendarDate) -> HomePeriod {
        switch kind {
        case .month: currentMonth(today: today)
        case .ytd: .ytd
        case .last12Months: .last12Months
        case .lastYear: .lastYear
        }
    }

    /// A whole calendar year. Last year maps to `.lastYear` so its segment stays selected.
    static func calendarYear(_ year: Int, today: CalendarDate) -> HomePeriod {
        year == today.year - 1 ? .lastYear : .year(year)
    }

    var kind: Kind? {
        switch self {
        case .month: .month
        case .ytd: .ytd
        case .last12Months: .last12Months
        case .lastYear: .lastYear
        case .year: nil
        }
    }

    func range(today: CalendarDate) -> DayRange {
        switch self {
        case let .month(year, month):
            let period = MonthPeriod(year: year, month: month)
            return DayRange(from: period.firstDay, to: min(period.lastDay(), today))
        case .ytd:
            return DayRange(from: CalendarDate(year: today.year, month: 1, day: 1), to: today)
        case .last12Months:
            let first = CalendarDate(year: today.year, month: today.month, day: 1).shifted(months: -11)
            return DayRange(from: first, to: today)
        case .lastYear:
            return Self.wholeYear(today.year - 1, today: today)
        case let .year(year):
            return Self.wholeYear(year, today: today)
        }
    }

    /// The same span one period earlier: the month before for a month, else the year before.
    /// A period still in progress compares against the same number of days.
    func previousRange(today: CalendarDate) -> DayRange {
        let current = range(today: today)
        return DayRange(
            from: current.from.shifted(months: -comparisonMonths),
            to: current.to.shifted(months: -comparisonMonths)
        )
    }

    /// The menu chip's title, such as "October 2026", "Jan 1 – Oct 9" or "2025".
    func title(today: CalendarDate) -> String {
        let range = range(today: today)
        switch self {
        case .month:
            return range.from.startDate().formatted(.dateTime.month(.wide).year())
        case .ytd:
            return (range.from.startDate()..<range.to.startDate()).formatted(.interval.month(.abbreviated).day())
        case .last12Months:
            return (range.from.startDate()..<range.to.startDate()).formatted(.interval.month(.abbreviated).year())
        case .lastYear, .year:
            return String(range.from.year)
        }
    }

    /// What the hero's change compares against.
    var comparisonLabel: String {
        switch self {
        case .month: String(localized: "vs. previous month")
        case .ytd: String(localized: "vs. same period last year")
        case .last12Months: String(localized: "vs. previous 12 months")
        case .lastYear, .year: String(localized: "vs. the year before")
        }
    }

    private var comparisonMonths: Int {
        if case .month = self { return 1 }
        return 12
    }

    private static func wholeYear(_ year: Int, today: CalendarDate) -> DayRange {
        DayRange(
            from: CalendarDate(year: year, month: 1, day: 1),
            to: min(CalendarDate(year: year, month: 12, day: 31), today)
        )
    }
}

extension CalendarDate {
    /// The same day `months` months away, clamped to that month's length. A month's last day
    /// maps to the target month's last day, so whole months compare with whole months.
    func shifted(months: Int) -> CalendarDate {
        let index = year * 12 + (month - 1) + months
        let target = MonthPeriod(year: index / 12, month: index % 12 + 1)
        let targetLastDay = target.lastDay()
        if self == MonthPeriod(year: year, month: month).lastDay() { return targetLastDay }
        return CalendarDate(year: target.year, month: target.month, day: min(day, targetLastDay.day))
    }
}
