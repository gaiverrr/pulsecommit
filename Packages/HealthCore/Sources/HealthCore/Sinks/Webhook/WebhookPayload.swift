import CryptoKit
import Foundation

enum WebhookPayload {
    static let schemaVersion = "1.0"

    struct Daily {
        let body: Data
        let idempotencyKey: String
    }

    private struct ManifestEntry: Encodable {
        let path: String
        let bytes: Int
    }

    static func daily(snapshot: DailySnapshot, files: [FileEntry]) throws -> Daily {
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        let relative = files.map { entry in
            (path: relativePath(entry.path, dayKey: dayKey), data: entry.data)
        }
        guard let summary = relative.first(where: { $0.path == "summary.json" })?.data else {
            throw WebhookSinkError.missingSummary
        }
        let markdown = relative.first(where: { $0.path == "summary.md" }).map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        let digest = SHA256.hash(data: summary).map { String(format: "%02x", $0) }.joined()
        let key = "pc-\(dayKey)-\(digest.prefix(12))"
        let manifest = relative.map { ManifestEntry(path: $0.path, bytes: $0.data.count) }

        var body = Data("{".utf8)
        body.append(field("schema_version", try encode(schemaVersion)))
        body.append(Data(",".utf8))
        body.append(field("event_type", try encode("daily_export")))
        body.append(Data(",".utf8))
        body.append(field("date", try encode(dayKey)))
        body.append(Data(",".utf8))
        body.append(field("idempotency_key", try encode(key)))
        body.append(Data(",".utf8))
        body.append(field("summary", summary))
        body.append(Data(",".utf8))
        body.append(field("summary_markdown", try encode(markdown)))
        body.append(Data(",".utf8))
        body.append(field("files", try encode(manifest)))
        body.append(Data("}".utf8))
        return Daily(body: body, idempotencyKey: key)
    }

    static func test(appVersion: String, sentAt: Date) throws -> Data {
        let formatter = ISO8601DateFormatter()
        let object: [String: String] = [
            "schema_version": schemaVersion,
            "event_type": "test",
            "sent_at": formatter.string(from: sentAt),
            "app_version": appVersion,
            "message": "Test request from Pulse Commit. It contains no Health data."
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func relativePath(_ path: String, dayKey: String) -> String {
        let prefix = dayKey + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private static func field(_ name: String, _ value: Data) -> Data {
        var data = Data("\"\(name)\":".utf8)
        data.append(value)
        return data
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
