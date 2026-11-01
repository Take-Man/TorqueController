import Foundation
import Testing
@testable import TorqueEngine

/// 小さな辞書のフィクスチャを作ってコンパイルする。ID は 0=BOS/EOS、1=名詞、2=助詞。
private func makeDictionary() throws -> TorqueDictionary {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("torque-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let dictionary = """
    こんばん\t1\t1\t3000\t今晩
    こんばん\t1\t1\t5000\tこんばん
    こんば\t1\t1\t7000\t今羽
    こんば\t1\t1\t6000\tコンバ
    こん\t1\t1\t4000\t紺
    に\t2\t2\t500\tに
    は\t2\t2\t500\tは
    には\t2\t2\t800\tには
    あめ\t1\t1\t3000\t雨
    あめ\t1\t1\t3500\t飴

    """
    try dictionary.write(to: directory.appendingPathComponent("dictionary00.txt"), atomically: true, encoding: .utf8)
    try "0 BOS/EOS,*,*,*,*,*,*\n1 名詞,一般,*,*,*,*,*\n2 助詞,格助詞,*,*,*,*,*\n"
        .write(to: directory.appendingPathComponent("id.def"), atomically: true, encoding: .utf8)
    // 行が右の語の右ID、列が左の語の左ID。名詞→助詞を安く、助詞→名詞は普通にする
    let matrix = [0, 100, 3000,
                  100, 500, 50,
                  100, 200, 100]
    try (["3"] + matrix.map(String.init)).joined(separator: "\n").appending("\n")
        .write(to: directory.appendingPathComponent("connection_single_column.txt"), atomically: true, encoding: .utf8)

    let output = directory.appendingPathComponent("test.dict")
    try DictionaryCompiler.compile(source: directory, output: output)
    return try TorqueDictionary(contentsOf: output)
}

@Test func columnsGoFromBunsetsuToShorterReadings() throws {
    let columns = Converter(dictionary: try makeDictionary()).columns(for: "こんばんには")
    #expect(columns.map(\.reading) == ["こんばんには", "こんばんに", "こんばん", "こんば", "こん"])
    #expect(columns[0].candidates.first?.surface == "今晩には")
    #expect(columns[1].candidates.first?.surface == "今晩に")
    #expect(columns[2].candidates.first?.surface == "今晩")
    #expect(Set(columns[3].candidates.map(\.surface)).isSuperset(of: ["コンバ", "今羽"]))
}

@Test func columnWithoutDictionaryEntriesIsSkipped() throws {
    let columns = Converter(dictionary: try makeDictionary()).columns(for: "こんばん")
    #expect(!columns.map(\.reading).contains("こ"))
}

@Test func onlyFirstBunsetsuIsConverted() throws {
    let columns = Converter(dictionary: try makeDictionary()).columns(for: "こんばんにあめ")
    #expect(columns.first?.reading == "こんばんに")
}

@Test func hiraganaAndKatakanaAreAlwaysCandidates() throws {
    let columns = Converter(dictionary: try makeDictionary()).columns(for: "あめ")
    let surfaces = columns[0].candidates.map(\.surface)
    #expect(surfaces.contains("あめ"))
    #expect(surfaces.contains("アメ"))
    #expect(surfaces.first == "雨")
}

@Test func scoreBreakdownAddsUp() throws {
    let columns = Converter(dictionary: try makeDictionary()).columns(for: "あめ")
    let rain = try #require(columns[0].candidates.first { $0.surface == "雨" })
    #expect(rain.dictionaryCost == 3000)
    #expect(rain.connectionCost == 100)
    #expect(rain.learningBonus == 0)
    #expect(rain.score == 3100)
}

@Test func unknownCharactersBecomeOneColumn() throws {
    let columns = Converter(dictionary: try makeDictionary()).columns(for: "abc")
    #expect(columns.map(\.reading) == ["abc"])
    #expect(columns[0].candidates.map(\.surface) == ["abc"])
}

@Test func emptyInputHasNoColumns() throws {
    #expect(Converter(dictionary: try makeDictionary()).columns(for: "").isEmpty)
}

@Test func learningMovesSelectedCandidateUp() throws {
    var learning = LearningModel()
    let date = Date(timeIntervalSince1970: 1_000_000)
    learning.record(reading: "あめ", surface: "飴", at: date)
    let columns = Converter(dictionary: try makeDictionary(), learning: learning).columns(for: "あめ", at: date)
    #expect(columns[0].candidates.first?.surface == "飴")
    #expect(columns[0].candidates.first?.learningBonus == 6000)
}

@Test func learningBonusGrowsWithCountAndDecaysWithAge() {
    var learning = LearningModel()
    let date = Date(timeIntervalSince1970: 1_000_000)
    learning.record(reading: "あ", surface: "亜", at: date)
    let once = learning.bonus(reading: "あ", surface: "亜", at: date)
    learning.record(reading: "あ", surface: "亜", at: date)
    let twice = learning.bonus(reading: "あ", surface: "亜", at: date)
    let later = learning.bonus(reading: "あ", surface: "亜", at: date.addingTimeInterval(30 * 86400))
    #expect(twice > once)
    #expect(later == twice / 2)
    #expect(learning.bonus(reading: "あ", surface: "阿", at: date) == 0)
}

@Test func learningRoundTripsThroughJSON() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("torque-\(UUID().uuidString)/learning.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var learning = LearningModel()
    let date = Date(timeIntervalSince1970: 1_000_000)
    learning.record(reading: "あめ", surface: "飴", at: date)
    try learning.save(to: url)
    let loaded = try LearningModel.load(from: url)
    #expect(loaded.bonus(reading: "あめ", surface: "飴", at: date) == 6000)
}

@Test func corruptDictionaryIsRejected() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("torque-\(UUID().uuidString).dict")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 0, count: 100).write(to: url)
    #expect(throws: TorqueDictionary.LoadError.self) {
        try TorqueDictionary(contentsOf: url)
    }
}

/// 実データの辞書があるときだけ確かめる。scripts/build-dictionary.sh で作る。
private let realDictionaryURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".build/dictionary/torque.dict")

@Test(.enabled(if: FileManager.default.fileExists(atPath: realDictionaryURL.path)))
func realDictionaryProducesDesignedColumnOrder() throws {
    let columns = Converter(dictionary: try TorqueDictionary(contentsOf: realDictionaryURL)).columns(for: "こんばんには")
    #expect(Array(columns.map(\.reading).prefix(4)) == ["こんばんには", "こんばんに", "こんばん", "こんば"])
    #expect(columns[0].candidates.map(\.surface).contains("今晩には"))
    #expect(columns[0].candidates.map(\.surface).contains("こんばんには"))
    #expect(columns[1].candidates.map(\.surface).contains("今晩に"))
    #expect(columns[2].candidates.map(\.surface).contains("今晩"))
    #expect(columns[3].candidates.map(\.surface).contains("コンバ"))
    #expect(columns[3].candidates.map(\.surface).contains("今羽"))
}
