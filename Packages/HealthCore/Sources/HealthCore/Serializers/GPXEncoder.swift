import Foundation

public struct GPXEncoder: Sendable {
    public init() {}

    public func encode(name: String, points: [RoutePointDTO]) -> Data {
        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"#
        xml += "\n"
        xml += #"<gpx version="1.1" creator="Pulse Commit" xmlns="http://www.topografix.com/GPX/1/1">"#
        xml += "\n  <trk>\n"
        xml += "    <name>\(Self.xmlEscape(name))</name>\n"
        xml += "    <trkseg>\n"
        for p in points {
            let lat = Self.format(p.latitude)
            let lon = Self.format(p.longitude)
            xml += "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\">\n"
            if let ele = p.elevationMeters {
                xml += "        <ele>\(Self.format(ele))</ele>\n"
            }
            xml += "        <time>\(Self.iso8601.string(from: p.time))</time>\n"
            xml += "      </trkpt>\n"
        }
        xml += "    </trkseg>\n"
        xml += "  </trk>\n"
        xml += "</gpx>\n"
        return Data(xml.utf8)
    }

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func format(_ value: Double) -> String {
        var s = String(format: "%.7f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func xmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}
