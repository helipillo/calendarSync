import Foundation

actor HxStoreFallbackService {
    func fetchEvents(calendarID: String, windowStart: Date, windowEnd: Date) async throws -> [OutlookEventRecord] {
        guard let scriptURL = resolveScriptURL() else {
            return []
        }

        let pythonURL = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            return []
        }

        let payload = HxStorePayload(
            calendarID: calendarID,
            windowStart: isoString(for: windowStart),
            windowEnd: isoString(for: windowEnd)
        )
        let payloadData = try JSONEncoder().encode(payload)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = pythonURL
            process.arguments = [scriptURL.path]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    do {
                        let decoded = try Self.decodeResponse(data)
                        continuation.resume(returning: decoded.events.map(\.model))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    let output = String(decoding: data, as: UTF8.self)
                    continuation.resume(throwing: HxStoreFallbackError.executionFailed(output))
                }
            }

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(payloadData)
                try inputPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func resolveScriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "hxstore_extract", withExtension: "py") {
            return bundled
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fallback = cwd.appendingPathComponent("CalendarBridge/Resources/hxstore_extract.py")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func isoString(for date: Date) -> String {
        Self.makeISO8601Formatter(withFractionalSeconds: false).string(from: date)
    }

    private static func decodeResponse(_ data: Data) throws -> HxStoreResponse {
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
        return try decoder.decode(HxStoreResponse.self, from: data)
    }

    private static func makeISO8601Formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

private struct HxStorePayload: Encodable {
    let calendarID: String
    let windowStart: String
    let windowEnd: String
}

private struct HxStoreResponse: Decodable {
    let events: [HxStoreEventDTO]
}

private struct HxStoreEventDTO: Decodable {
    let recordID: String
    let sourceCalendarID: String
    let sourceCalendarName: String
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
            eventID: "hx-\(recordID)",
            exchangeID: nil,
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

enum HxStoreFallbackError: LocalizedError {
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .executionFailed(output):
            return output.isEmpty ? "HxStore fallback failed" : output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
