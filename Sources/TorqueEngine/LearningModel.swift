import Foundation

/// 「読み・表記」の組ごとの選択回数と最終使用時刻。スコアから引く補正を計算する。
public struct LearningModel: Codable, Sendable {
    private struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private static let baseBonus = 6000.0
    private static let bonusPerDoubling = 1000.0
    private static let halfLifeDays = 30.0

    private var records: [String: Record] = [:]

    public init() {}

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TorqueController/learning.json")
    }

    public mutating func record(reading: String, surface: String, at date: Date = Date()) {
        var record = records[Self.key(reading, surface)] ?? Record(count: 0, lastUsed: date)
        record.count += 1
        record.lastUsed = date
        records[Self.key(reading, surface)] = record
    }

    /// 回数が増えるほど大きく、使っていない期間が長いほど小さくなる。
    public func bonus(reading: String, surface: String, at date: Date = Date()) -> Int {
        guard let record = records[Self.key(reading, surface)] else { return 0 }
        let days = max(0, date.timeIntervalSince(record.lastUsed) / 86400)
        let decay = pow(0.5, days / Self.halfLifeDays)
        return Int((Self.baseBonus + Self.bonusPerDoubling * log2(Double(record.count))) * decay)
    }

    public static func load(from url: URL) throws -> LearningModel {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LearningModel.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    private static func key(_ reading: String, _ surface: String) -> String {
        reading + "\t" + surface
    }
}
