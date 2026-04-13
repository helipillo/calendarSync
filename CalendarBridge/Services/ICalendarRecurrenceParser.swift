import EventKit
import Foundation

struct ICalendarRecurrenceParser {
    func recurrenceRules(from icalendarData: String?) -> [EKRecurrenceRule]? {
        guard let icalendarData, !icalendarData.isEmpty else { return nil }
        let unfoldedLines = unfoldICS(icalendarData)
        let rruleLines = unfoldedLines.filter { $0.uppercased().hasPrefix("RRULE") }
        guard !rruleLines.isEmpty else { return nil }

        return rruleLines.compactMap { buildRule(from: $0) }
    }

    private func buildRule(from line: String) -> EKRecurrenceRule? {
        guard let value = line.split(separator: ":", maxSplits: 1).last.map(String.init) else { return nil }
        let components = Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { entry -> (String, String)? in
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].uppercased(), parts[1])
        })

        guard let freq = components["FREQ"]?.uppercased() else { return nil }
        let interval = Int(components["INTERVAL"] ?? "1") ?? 1
        let end = buildEnd(from: components)

        switch freq {
        case "DAILY":
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: interval,
                end: end
            )

        case "WEEKLY":
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: interval,
                daysOfTheWeek: parseWeekdays(components["BYDAY"]),
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )

        case "MONTHLY":
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: interval,
                daysOfTheWeek: parseMonthlyWeekdays(components["BYDAY"], setPos: components["BYSETPOS"]),
                daysOfTheMonth: parseIntegers(components["BYMONTHDAY"]),
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: parseIntegers(components["BYSETPOS"]),
                end: end
            )

        case "YEARLY":
            return EKRecurrenceRule(
                recurrenceWith: .yearly,
                interval: interval,
                daysOfTheWeek: parseMonthlyWeekdays(components["BYDAY"], setPos: components["BYSETPOS"]),
                daysOfTheMonth: parseIntegers(components["BYMONTHDAY"]),
                monthsOfTheYear: parseIntegers(components["BYMONTH"]),
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: parseIntegers(components["BYSETPOS"]),
                end: end
            )

        default:
            return nil
        }
    }

    private func buildEnd(from components: [String: String]) -> EKRecurrenceEnd? {
        if let countString = components["COUNT"], let count = Int(countString) {
            return EKRecurrenceEnd(occurrenceCount: count)
        }

        if let until = components["UNTIL"], let endDate = parseICSDate(until) {
            return EKRecurrenceEnd(end: endDate)
        }

        return nil
    }

    private func parseWeekdays(_ value: String?) -> [EKRecurrenceDayOfWeek]? {
        guard let value else { return nil }
        let items = value.split(separator: ",").compactMap { parseWeekday(String($0), ordinal: nil) }
        return items.isEmpty ? nil : items
    }

    private func parseMonthlyWeekdays(_ byDay: String?, setPos: String?) -> [EKRecurrenceDayOfWeek]? {
        guard let byDay else { return nil }
        let ordinal = parseIntegers(setPos)?.first?.intValue
        let items = byDay.split(separator: ",").compactMap { parseWeekday(String($0), ordinal: ordinal) }
        return items.isEmpty ? nil : items
    }

    private func parseWeekday(_ token: String, ordinal: Int?) -> EKRecurrenceDayOfWeek? {
        let letters = token.suffix(2).uppercased()
        let day: EKWeekday
        switch letters {
        case "SU": day = .sunday
        case "MO": day = .monday
        case "TU": day = .tuesday
        case "WE": day = .wednesday
        case "TH": day = .thursday
        case "FR": day = .friday
        case "SA": day = .saturday
        default: return nil
        }

        if let explicitOrdinal = Int(token.dropLast(2)) {
            return EKRecurrenceDayOfWeek(day, weekNumber: explicitOrdinal)
        }

        if let ordinal {
            return EKRecurrenceDayOfWeek(day, weekNumber: ordinal)
        }

        return EKRecurrenceDayOfWeek(day)
    }

    private func parseIntegers(_ value: String?) -> [NSNumber]? {
        guard let value else { return nil }
        let numbers = value.split(separator: ",").compactMap { token -> NSNumber? in
            guard let integer = Int(String(token)) else { return nil }
            return NSNumber(value: integer)
        }
        return numbers.isEmpty ? nil : numbers
    }

    private func parseICSDate(_ raw: String) -> Date? {
        let formatters = [
            makeFormatter("yyyyMMdd'T'HHmmssX"),
            makeFormatter("yyyyMMdd'T'HHmmss"),
            makeFormatter("yyyyMMdd")
        ]

        for formatter in formatters {
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private func unfoldICS(_ ics: String) -> [String] {
        var result: [String] = []
        for rawLine in ics.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard !result.isEmpty else { continue }
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }
}
