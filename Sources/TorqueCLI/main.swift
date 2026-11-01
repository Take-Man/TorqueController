import Foundation
import TorqueEngine

let usage = """
使い方:
  torque-cli build-dictionary <元データのフォルダ> <出力ファイル>
  torque-cli [--dict <辞書>] [--learning <学習ファイル>] [--top <列ごとの表示数>] [--repeat <回数>] <読み>
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func buildDictionary(source: String, output: String) throws {
    let summary = try DictionaryCompiler.compile(source: URL(fileURLWithPath: source), output: URL(fileURLWithPath: output))
    print("読み \(summary.readingCount) 件、語 \(summary.entryCount) 件、品詞ID \(summary.posCount) 個、\(summary.byteCount / 1_000_000) MB: \(output)")
}

func convert(arguments: [String]) throws {
    var dictionaryPath = ".build/dictionary/torque.dict"
    var learningURL = LearningModel.defaultURL
    var top = 6
    var repeatCount = 1
    var reading: String?

    var iterator = arguments.makeIterator()
    func nextValue() -> String {
        guard let value = iterator.next() else { fail(usage) }
        return value
    }
    func nextNumber() -> Int {
        guard let number = Int(nextValue()) else { fail(usage) }
        return number
    }
    while let argument = iterator.next() {
        switch argument {
        case "--dict": dictionaryPath = nextValue()
        case "--learning": learningURL = URL(fileURLWithPath: nextValue())
        case "--top": top = nextNumber()
        case "--repeat": repeatCount = nextNumber()
        default: reading = argument
        }
    }
    guard let reading else { fail(usage) }

    let learning = (try? LearningModel.load(from: learningURL)) ?? LearningModel()
    let converter = Converter(dictionary: try TorqueDictionary(contentsOf: URL(fileURLWithPath: dictionaryPath)), learning: learning)

    var columns: [CandidateColumn] = []
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        for _ in 0..<repeatCount {
            columns = converter.columns(for: reading)
        }
    }

    for (index, column) in columns.enumerated() {
        print("列\(index + 1) 読み「\(column.reading)」 候補 \(column.candidates.count) 件")
        for candidate in column.candidates.prefix(top) {
            print("  \(candidate.surface)\tスコア \(candidate.score) = 辞書 \(candidate.dictionaryCost) + 接続 \(candidate.connectionCost) - 学習 \(candidate.learningBonus)")
        }
    }
    let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    print(String(format: "変換 1 回あたり %.2f ms(%d 回の平均)", milliseconds / Double(repeatCount), repeatCount))
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.first == "build-dictionary" {
        guard arguments.count == 3 else { fail(usage) }
        try buildDictionary(source: arguments[1], output: arguments[2])
    } else {
        try convert(arguments: arguments)
    }
} catch {
    fail("\(error)")
}
