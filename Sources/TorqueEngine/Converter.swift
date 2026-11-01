import Foundation

/// 候補とスコアの内訳。スコア = 辞書コスト + 接続コスト - 学習補正。小さいほど上位。
public struct Candidate: Equatable, Sendable {
    public let surface: String
    public let dictionaryCost: Int
    public let connectionCost: Int
    public let learningBonus: Int

    public var score: Int { dictionaryCost + connectionCost - learningBonus }
}

/// 同じ読みの候補の列。
public struct CandidateColumn: Equatable, Sendable {
    public let reading: String
    public let candidates: [Candidate]
}

/// 読みの先頭から、列ごとの候補を作る。先頭は最良経路の最初の文節で、内側の列ほど読みが長い。
public struct Converter: Sendable {
    /// 辞書で引く読みの長さの上限。
    private static let maxWordLength = 32
    private static let bosID: UInt16 = 0
    private static let unknownCost = 20000
    /// 辞書にないひらがな・カタカナの候補に使うコスト。
    private static let kanaFallbackCost = 12000

    private let dictionary: TorqueDictionary
    public var learning: LearningModel

    public init(dictionary: TorqueDictionary, learning: LearningModel = LearningModel()) {
        self.dictionary = dictionary
        self.learning = learning
    }

    public func columns(for reading: String, at date: Date = Date()) -> [CandidateColumn] {
        let input = Input(reading)
        guard input.count > 0 else { return [] }
        let path = bestPath(input)
        guard let head = path.first else { return [] }

        // 語彙にない文字の並び(英数字など)は、そのままの1列にする
        guard let headEntry = head.entry else {
            return [column(input, end: head.end, functional: [], headEntries: 0..<0, date: date)]
        }

        var bunsetsuEnd = head.end
        for word in path.dropFirst() {
            guard let index = word.entry, dictionary.isFunctional(id: dictionary.entry(at: index).leftID) else { break }
            bunsetsuEnd = word.end
        }

        let headEntries = input.entries(in: dictionary, from: 0, to: head.end)
        let tails = functionalTails(input, from: head.end, to: bunsetsuEnd, previousRightID: dictionary.entry(at: headEntry).rightID)

        var result: [CandidateColumn] = []
        var end = bunsetsuEnd
        while end > head.end {
            if let functional = tails[end] {
                result.append(column(input, end: end, functional: functional, headEntries: headEntries, date: date))
            }
            end -= 1
        }
        result.append(column(input, end: head.end, functional: [], headEntries: headEntries, date: date))
        end = head.end - 1
        while end > 0 {
            if !input.entries(in: dictionary, from: 0, to: end).isEmpty {
                result.append(column(input, end: end, functional: [], headEntries: 0..<0, date: date))
            }
            end -= 1
        }
        return result
    }

    // MARK: - ビタビ探索

    private struct PathWord {
        let end: Int
        /// 辞書の語の番号。語彙にない文字の並びなら nil。
        let entry: Int?
    }

    private struct Node {
        let end: Int
        let entry: Int?
        let previous: Int
        let total: Int
    }

    private func bestPath(_ input: Input) -> [PathWord] {
        var nodes = [Node(end: 0, entry: nil, previous: -1, total: 0)]
        var ends = [[UInt16: Int]](repeating: [:], count: input.count + 1)
        ends[0][Self.bosID] = 0

        var bestForLeft = [Int32](repeating: -1, count: dictionary.idCount)
        var bestStamp = [Int32](repeating: -1, count: dictionary.idCount)
        var bestTotal = [Int](repeating: 0, count: dictionary.idCount)

        func add(_ rightID: UInt16, end: Int, entry: Int?, previous: Int, total: Int) {
            if let existing = ends[end][rightID], nodes[existing].total <= total { return }
            ends[end][rightID] = nodes.count
            nodes.append(Node(end: end, entry: entry, previous: previous, total: total))
        }

        for start in 0..<input.count where !ends[start].isEmpty {
            let previous = Array(ends[start])
            func bestConnection(left: UInt16) -> (node: Int, total: Int) {
                let index = Int(left)
                if bestStamp[index] == Int32(start) {
                    return (Int(bestForLeft[index]), bestTotal[index])
                }
                var bestNode = -1
                var best = Int.max
                for (rightID, node) in previous {
                    let total = nodes[node].total + dictionary.connectionCost(right: rightID, left: left)
                    if total < best {
                        best = total
                        bestNode = node
                    }
                }
                bestStamp[index] = Int32(start)
                bestForLeft[index] = Int32(bestNode)
                bestTotal[index] = best
                return (bestNode, best)
            }

            var hasSingleCharacterWord = false
            for end in (start + 1)...min(input.count, start + Self.maxWordLength) {
                let range = input.entries(in: dictionary, from: start, to: end)
                if end == start + 1, !range.isEmpty {
                    hasSingleCharacterWord = true
                }
                for index in range {
                    let entry = dictionary.entry(at: index)
                    let connection = bestConnection(left: entry.leftID)
                    add(entry.rightID, end: end, entry: index, previous: connection.node, total: connection.total + Int(entry.cost))
                }
            }

            // 語彙にない文字は、同じ種類の文字の並びを1語として必ず通れるようにする
            let runEnd = input.nonKanaRunEnd(from: start)
            if runEnd > start || !hasSingleCharacterWord {
                let connection = bestConnection(left: dictionary.unknownID)
                add(dictionary.unknownID, end: max(runEnd, start + 1), entry: nil, previous: connection.node, total: connection.total + Self.unknownCost)
            }
        }

        var bestNode = -1
        var best = Int.max
        for (rightID, node) in ends[input.count] {
            let total = nodes[node].total + dictionary.connectionCost(right: rightID, left: Self.bosID)
            if total < best {
                best = total
                bestNode = node
            }
        }

        var path: [PathWord] = []
        var current = bestNode
        while current > 0 {
            path.append(PathWord(end: nodes[current].end, entry: nodes[current].entry))
            current = nodes[current].previous
        }
        return path.reversed()
    }

    // MARK: - 列の生成

    /// 自立語の直後から、付属語だけで区切れる位置ごとに、最小コストの付属語の並びを求める。
    private func functionalTails(_ input: Input, from start: Int, to limit: Int, previousRightID: UInt16) -> [Int: [Int]] {
        var best: [Int: (total: Int, rightID: UInt16, words: [Int])] = [start: (0, previousRightID, [])]
        var position = start
        while position < limit {
            if let current = best[position] {
                for end in (position + 1)...limit {
                    for index in input.entries(in: dictionary, from: position, to: end) {
                        let entry = dictionary.entry(at: index)
                        guard dictionary.isFunctional(id: entry.leftID) else { continue }
                        let total = current.total + Int(entry.cost) + dictionary.connectionCost(right: current.rightID, left: entry.leftID)
                        if best[end].map({ total < $0.total }) ?? true {
                            best[end] = (total, entry.rightID, current.words + [index])
                        }
                    }
                }
            }
            position += 1
        }
        best[start] = nil
        return best.mapValues(\.words)
    }

    private func column(_ input: Input, end: Int, functional: [Int], headEntries: Range<Int>, date: Date) -> CandidateColumn {
        let reading = input.string(from: 0, to: end)
        var best: [String: (dictionary: Int, connection: Int)] = [:]
        func add(_ surface: String, dictionaryCost: Int, connectionCost: Int) {
            if let existing = best[surface], existing.dictionary + existing.connection <= dictionaryCost + connectionCost { return }
            best[surface] = (dictionaryCost, connectionCost)
        }

        for index in input.entries(in: dictionary, from: 0, to: end) {
            let entry = dictionary.entry(at: index)
            add(dictionary.surface(of: entry), dictionaryCost: Int(entry.cost), connectionCost: dictionary.connectionCost(right: Self.bosID, left: entry.leftID))
        }

        if !functional.isEmpty {
            let tail = functional.map { dictionary.entry(at: $0) }
            let tailSurface = tail.map { dictionary.surface(of: $0) }.joined()
            let tailCost = tail.reduce(0) { $0 + Int($1.cost) }
            var tailConnection = 0
            for (left, right) in zip(tail, tail.dropFirst()) {
                tailConnection += dictionary.connectionCost(right: left.rightID, left: right.leftID)
            }
            for index in headEntries {
                let entry = dictionary.entry(at: index)
                let connection = dictionary.connectionCost(right: Self.bosID, left: entry.leftID)
                    + dictionary.connectionCost(right: entry.rightID, left: tail[0].leftID)
                    + tailConnection
                add(dictionary.surface(of: entry) + tailSurface, dictionaryCost: Int(entry.cost) + tailCost, connectionCost: connection)
            }
        }

        // ひらがなとカタカナは必ず候補に含める
        add(reading, dictionaryCost: Self.kanaFallbackCost, connectionCost: 0)
        add(Input.katakana(reading), dictionaryCost: Self.kanaFallbackCost, connectionCost: 0)

        let candidates = best.map { surface, costs in
            Candidate(
                surface: surface,
                dictionaryCost: costs.dictionary,
                connectionCost: costs.connection,
                learningBonus: learning.bonus(reading: reading, surface: surface, at: date)
            )
        }
        .sorted { ($0.score, $0.surface) < ($1.score, $1.surface) }
        return CandidateColumn(reading: reading, candidates: candidates)
    }
}

/// 入力の読み。文字の区切りと UTF-8 の位置を持ち、辞書を引く。
private struct Input {
    let characters: [Character]
    let bytes: [UInt8]
    /// 文字の番号から UTF-8 の位置への対応。
    let offsets: [Int]

    var count: Int { characters.count }

    init(_ reading: String) {
        characters = Array(reading)
        var bytes: [UInt8] = []
        var offsets = [0]
        for character in characters {
            bytes.append(contentsOf: character.utf8)
            offsets.append(bytes.count)
        }
        self.bytes = bytes
        self.offsets = offsets
    }

    func entries(in dictionary: TorqueDictionary, from start: Int, to end: Int) -> Range<Int> {
        bytes.withUnsafeBufferPointer { buffer in
            dictionary.entries(forReading: UnsafeBufferPointer(rebasing: buffer[offsets[start]..<offsets[end]]))
        }
    }

    func string(from start: Int, to end: Int) -> String {
        String(characters[start..<end])
    }

    /// start から続く、ひらがな以外の文字の並びの終わり。start がひらがなら start。
    func nonKanaRunEnd(from start: Int) -> Int {
        var end = start
        while end < count, !Self.isKana(characters[end]) {
            end += 1
        }
        return end
    }

    private static func isKana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) || $0 == "ー" }
    }

    static func katakana(_ string: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            if (0x3041...0x3096).contains(scalar.value), let converted = Unicode.Scalar(scalar.value + 0x60) {
                result.append(converted)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }
}
