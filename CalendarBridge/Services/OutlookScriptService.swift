import Foundation

actor OutlookScriptService {
    private enum Constants {
        static let historyLookbackDays = 30
        static let futureHorizonDays = 365
    }

    private let hxStoreFallbackService = HxStoreFallbackService()

    func fetchCalendars() async throws -> [OutlookCalendarRef] {
        let script = """
        const outlook = Application('Microsoft Outlook');
        const calendars = outlook.calendars().map(calendar => ({
          id: String(calendar.id()),
          name: String(calendar.name())
        }));
        JSON.stringify(calendars);
        """

        let data = try await runJXA(script)
        return try decode([OutlookCalendarRef].self, from: data)
    }

    func fetchEvents(calendarID: String) async throws -> [OutlookEventRecord] {
        let windowStart = Calendar.current.date(byAdding: .day, value: -Constants.historyLookbackDays, to: Date()) ?? Date()
        let windowEnd = Calendar.current.date(byAdding: .day, value: Constants.futureHorizonDays, to: Date()) ?? Date()

        do {
            let automationRecords = try await fetchEventsViaAutomation(
                calendarID: calendarID,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            if !automationRecords.isEmpty {
                return automationRecords
            }
        } catch {
            let fallbackRecords = try await hxStoreFallbackService.fetchEvents(
                calendarID: calendarID,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            if !fallbackRecords.isEmpty {
                return fallbackRecords
            }
            throw error
        }

        return try await hxStoreFallbackService.fetchEvents(
            calendarID: calendarID,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
    }

    private func fetchEventsViaAutomation(calendarID: String, windowStart: Date, windowEnd: Date) async throws -> [OutlookEventRecord] {
        let payload = [
            "calendarID": calendarID,
            "windowStart": isoString(for: windowStart),
            "windowEnd": isoString(for: windowEnd)
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let payloadString = String(decoding: payloadData, as: UTF8.self)

        let script = """
        function isoOrNull(value) {
          return value ? value.toISOString() : null;
        }

        const args = \(payloadString);
        const outlook = Application('Microsoft Outlook');
        const calendars = outlook.calendars();
        const calendar = calendars.find(item => String(item.id()) === String(args.calendarID));

        if (!calendar) {
          throw new Error(`Outlook calendar not found for id ${args.calendarID}`);
        }

        const fromDate = new Date(args.windowStart);
        const toDate = new Date(args.windowEnd);

        const events = calendar.calendarEvents()
          .filter(event => {
            try {
              const start = event.startTime();
              const end = event.endTime();
              return (start < toDate && end > fromDate) || event.isRecurring();
            } catch (error) {
              return false;
            }
          })
          .map(event => ({
            sourceCalendarID: String(calendar.id()),
            sourceCalendarName: String(calendar.name()),
            eventID: String(event.id()),
            exchangeID: (() => { try { return String(event.exchangeId()); } catch (error) { return null; } })(),
            subject: (() => { try { return String(event.subject() || ''); } catch (error) { return ''; } })(),
            startDate: isoOrNull((() => { try { return event.startTime(); } catch (error) { return null; } })()),
            endDate: isoOrNull((() => { try { return event.endTime(); } catch (error) { return null; } })()),
            location: (() => { try { return String(event.location() || ''); } catch (error) { return null; } })(),
            notes: (() => { try { return String(event.plainTextContent() || ''); } catch (error) { return null; } })(),
            allDay: (() => { try { return Boolean(event.allDayFlag()); } catch (error) { return false; } })(),
            modificationDate: isoOrNull((() => { try { return event.modificationDate(); } catch (error) { return null; } })()),
            icalendarData: (() => { try { return String(event.icalendarData() || ''); } catch (error) { return null; } })()
          }))
          .filter(event => event.startDate && event.endDate);

        JSON.stringify(events);
        """

        let data = try await runJXA(script)
        var records = try decode([OutlookEventDTO].self, from: data).map { $0.model }
        records.sort { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            return lhs.startDate < rhs.startDate
        }
        return records
    }

    private func runJXA(_ source: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript"]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let output = String(decoding: data, as: UTF8.self)
                    continuation.resume(throwing: OutlookScriptError.executionFailed(output))
                }
            }

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(Data(source.utf8))
                try inputPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.makeISO8601Formatter(withFractionalSeconds: true).date(from: value)
                ?? Self.makeISO8601Formatter(withFractionalSeconds: false).date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        return try decoder.decode(type, from: data)
    }

    private func isoString(for date: Date) -> String {
        Self.makeISO8601Formatter(withFractionalSeconds: false).string(from: date)
    }

    private static func makeISO8601Formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

private struct OutlookEventDTO: Decodable {
    let sourceCalendarID: String
    let sourceCalendarName: String
    let eventID: String
    let exchangeID: String?
    let subject: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let allDay: Bool
    let modificationDate: Date?
    let icalendarData: String?

    var model: OutlookEventRecord {
        OutlookEventRecord(
            sourceCalendarID: sourceCalendarID,
            sourceCalendarName: sourceCalendarName,
            eventID: eventID,
            exchangeID: exchangeID,
            subject: subject,
            startDate: startDate,
            endDate: endDate,
            location: location?.nilIfBlank,
            notes: notes?.nilIfBlank,
            allDay: allDay,
            modificationDate: modificationDate,
            icalendarData: icalendarData?.nilIfBlank
        )
    }
}

enum OutlookScriptError: LocalizedError {
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .executionFailed(output):
            return output.isEmpty ? "Outlook scripting failed" : output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
