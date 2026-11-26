import Foundation
import CoreFoundation

struct PrepTransferItem: Codable, Equatable {
    let name: String
    let minutes: Int
}

enum PrepCode {
    static let prefix = "DP1:"
    static let maxPayload = 8 * 1024
    static let maxItems = 30
    static let maxFile = 2 * 1024 * 1024

    enum Invalid: Error { case format, limit }

    static func cleanedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return name
    }

    static func encode(_ items: [PrepTransferItem]) throws -> String {
        guard !items.isEmpty, items.count <= maxItems else { throw Invalid.limit }
        let clean = try items.map { item in
            guard let name = cleanedName(item.name), (1...DinnerMath.maxMinutes).contains(item.minutes)
            else { throw Invalid.format }
            return PrepTransferItem(name: name, minutes: item.minutes)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(clean)
        guard data.count <= maxPayload else { throw Invalid.limit }
        return prefix + base64URL(data)
    }

    static func decode(_ input: String) throws -> [PrepTransferItem] {
        var code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.hasPrefix(prefix), let r = code.range(of: prefix) {
            let tail = code[r.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
            code = prefix + tail
        }
        guard code.hasPrefix(prefix) else { throw Invalid.format }
        let payload = String(code.dropFirst(prefix.count))
        guard !payload.isEmpty, payload.utf8.count <= (maxPayload * 4 + 2) / 3 else { throw Invalid.limit }
        guard payload.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }), payload.count % 4 != 1 else { throw Invalid.format }
        let padded = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), base64URL(data) == payload,
              data.count <= maxPayload, String(data: data, encoding: .utf8) != nil,
              let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !values.isEmpty, values.count <= maxItems else { throw Invalid.format }
        return try values.map { value in
            guard Set(value.keys) == ["name", "minutes"],
                  let rawName = value["name"] as? String, let name = cleanedName(rawName),
                  let number = value["minutes"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let minutes = Int(number.stringValue), (1...DinnerMath.maxMinutes).contains(minutes)
            else { throw Invalid.format }
            return PrepTransferItem(name: name, minutes: minutes)
        }
    }

    static func codes(for items: [PrepTransferItem]) throws -> [String] {
        var codes: [String] = []
        var batch: [PrepTransferItem] = []
        for item in items {
            if let _ = try? encode(batch + [item]) {
                batch.append(item)
            } else {
                codes.append(try encode(batch))
                batch = [item]
            }
        }
        if !batch.isEmpty { codes.append(try encode(batch)) }
        return codes
    }

    static func decodeFile(_ data: Data) throws -> [PrepTransferItem] {
        guard data.count <= maxFile, let text = String(data: data, encoding: .utf8) else { throw Invalid.limit }
        let codes = text.split(whereSeparator: \.isNewline)
        guard !codes.isEmpty else { throw Invalid.format }
        return try codes.flatMap { try decode(String($0)) }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct PrepImport: Equatable {
    struct Row: Identifiable, Equatable {
        let id: Int
        let item: PrepTransferItem
        let status: Status
    }

    enum Status: Equatable { case available, sameName, duplicate, overLimit }

    let rows: [Row]

    var accepted: [PrepTransferItem] {
        rows.filter { $0.status == .available || $0.status == .sameName }.map(\.item)
    }

    var skippedDuplicates: Int { rows.filter { $0.status == .duplicate }.count }
    var skippedLimit: Int { rows.filter { $0.status == .overLimit }.count }

    init(incoming: [PrepTransferItem], existing: [PrepItem], hasPro: Bool) {
        func comparable(_ name: String) -> String {
            name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive],
                                                               locale: Locale(identifier: "en_US_POSIX"))
        }
        var seen: [String: Set<Int>] = [:]
        for item in existing {
            guard let minutes = item.minutes else { continue }
            seen[comparable(item.displayName), default: []].insert(minutes)
        }
        var slots = PrepAccess.availableSlots(currentCount: existing.filter { !$0.builtIn }.count, hasPro: hasPro)
        rows = incoming.enumerated().map { index, item in
            let name = comparable(item.name)
            let status: Status
            if seen[name]?.contains(item.minutes) == true {
                status = .duplicate
            } else if slots == 0 {
                status = .overLimit
            } else {
                status = seen[name] == nil ? .available : .sameName
                seen[name, default: []].insert(item.minutes)
                slots -= 1
            }
            return Row(id: index, item: item, status: status)
        }
    }
}
