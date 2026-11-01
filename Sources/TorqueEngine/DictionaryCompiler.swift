import Foundation

/// Mozc の dictionary_oss のテキストを、TorqueDictionary が読むバイナリに変換する。
public enum DictionaryCompiler {
    public enum CompileError: Error, CustomStringConvertible {
        case malformed(String)

        public var description: String {
            switch self {
            case .malformed(let message): "辞書データの形式が不正です: \(message)"
            }
        }
    }

    private static let functionalPrefixes = ["助詞,", "助動詞,", "動詞,接尾,", "動詞,非自立,"]

    private struct RawEntry {
        let leftID: UInt16
        let rightID: UInt16
        let cost: Int16
        let surface: [UInt8]
    }

    public struct Summary: Sendable {
        public let readingCount: Int
        public let entryCount: Int
        public let posCount: Int
        public let byteCount: Int
    }

    /// source には dictionary00.txt〜、connection_single_column.txt、id.def があること。
    @discardableResult
    public static func compile(source: URL, output: URL) throws -> Summary {
        let names = try FileManager.default.contentsOfDirectory(atPath: source.path)
        let dictionaryNames = names.filter { $0.hasPrefix("dictionary") && $0.hasSuffix(".txt") }.sorted()
        guard !dictionaryNames.isEmpty else {
            throw CompileError.malformed("dictionary*.txt がありません")
        }

        var grouped: [[UInt8]: [RawEntry]] = [:]
        for name in dictionaryNames {
            try parseDictionary(source.appendingPathComponent(name), into: &grouped)
        }
        let functional = try parseFunctionalFlags(source.appendingPathComponent("id.def"))
        let (connectionSize, connection) = try parseConnection(source.appendingPathComponent("connection_single_column.txt"))
        guard connectionSize == functional.flags.count else {
            throw CompileError.malformed("接続表の大きさ \(connectionSize) と id.def の件数 \(functional.flags.count) が違います")
        }

        let readings = grouped.keys.sorted { $0.lexicographicallyPrecedes($1) }
        var strings: [UInt8] = []
        var stringOffsets: [[UInt8]: UInt32] = [:]
        func intern(_ bytes: [UInt8]) -> UInt32 {
            if let offset = stringOffsets[bytes] { return offset }
            let offset = UInt32(strings.count)
            strings.append(contentsOf: bytes)
            stringOffsets[bytes] = offset
            return offset
        }

        var readingTable: [UInt32] = []
        var entryTable: [UInt8] = []
        var entryCount: UInt32 = 0
        for reading in readings {
            readingTable.append(intern(reading))
            readingTable.append(UInt32(reading.count))
            readingTable.append(entryCount)
            for entry in grouped[reading] ?? [] {
                entryTable.appendLittleEndian(intern(entry.surface))
                entryTable.appendLittleEndian(UInt16(entry.surface.count))
                entryTable.appendLittleEndian(entry.leftID)
                entryTable.appendLittleEndian(entry.rightID)
                entryTable.appendLittleEndian(UInt16(bitPattern: entry.cost))
                entryCount += 1
            }
        }
        readingTable.append(UInt32(strings.count))
        readingTable.append(0)
        readingTable.append(entryCount)

        var file: [UInt8] = []
        file.reserveCapacity(entryTable.count + strings.count + connection.count * 2 + readingTable.count * 4)
        file.appendLittleEndian(TorqueDictionary.magic)
        file.appendLittleEndian(UInt32(readings.count))
        file.appendLittleEndian(entryCount)
        file.appendLittleEndian(UInt32(strings.count))
        file.appendLittleEndian(UInt32(connectionSize))
        file.appendLittleEndian(UInt32(functional.unknownID))
        for flag in functional.flags {
            file.append(flag ? 1 : 0)
        }
        file.padToAlignment(4)
        for value in readingTable {
            file.appendLittleEndian(value)
        }
        file.append(contentsOf: entryTable)
        file.append(contentsOf: strings)
        file.padToAlignment(2)
        for value in connection {
            file.appendLittleEndian(UInt16(bitPattern: value))
        }

        try Data(file).write(to: output, options: .atomic)
        return Summary(readingCount: readings.count, entryCount: Int(entryCount), posCount: connectionSize, byteCount: file.count)
    }

    private static func parseDictionary(_ url: URL, into grouped: inout [[UInt8]: [RawEntry]]) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5,
                  let left = UInt16(fields[1]), let right = UInt16(fields[2]), let cost = Int16(fields[3])
            else {
                throw CompileError.malformed("\(url.lastPathComponent): \(line)")
            }
            let entry = RawEntry(leftID: left, rightID: right, cost: cost, surface: Array(fields[4].utf8))
            grouped[Array(fields[0].utf8), default: []].append(entry)
        }
    }

    /// 助詞、助動詞、動詞の接尾・非自立の ID を付属語とする。未知語には名詞の一般の ID を使う。
    private static func parseFunctionalFlags(_ url: URL) throws -> (flags: [Bool], unknownID: Int) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var flags: [Bool] = []
        var unknownID: Int?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, Int(parts[0]) == flags.count else {
                throw CompileError.malformed("id.def: \(line)")
            }
            flags.append(functionalPrefixes.contains { parts[1].hasPrefix($0) })
            if unknownID == nil, parts[1].hasPrefix("名詞,一般,") {
                unknownID = flags.count - 1
            }
        }
        guard let unknownID else {
            throw CompileError.malformed("id.def に名詞,一般がありません")
        }
        return (flags, unknownID)
    }

    /// 1行目が大きさ N、以降が N×N 個の接続コスト。
    private static func parseConnection(_ url: URL) throws -> (size: Int, costs: [Int16]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n").makeIterator()
        guard let first = lines.next(), let size = Int(first) else {
            throw CompileError.malformed("接続表の1行目")
        }
        var costs: [Int16] = []
        costs.reserveCapacity(size * size)
        while let line = lines.next() {
            guard let cost = Int16(line) else {
                throw CompileError.malformed("接続表: \(line)")
            }
            costs.append(cost)
        }
        guard costs.count == size * size else {
            throw CompileError.malformed("接続表の件数 \(costs.count) が \(size)×\(size) ではありません")
        }
        return (size, costs)
    }
}

private extension Array where Element == UInt8 {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func padToAlignment(_ alignment: Int) {
        while count % alignment != 0 {
            append(0)
        }
    }
}
