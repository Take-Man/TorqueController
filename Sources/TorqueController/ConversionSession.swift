import TorqueEngine

/// 1回の変換の状態。選んだ候補の履歴と、残りの読みの候補の列を持つ。
struct ConversionSession {
    /// 列ごとの候補の数。外側の列ほど1つずつ増やして、全体を扇形にする。
    static func pageSize(column: Int) -> Int {
        5 + column
    }

    struct Selection: Equatable {
        let reading: String
        let surface: String
    }

    private(set) var selections: [Selection] = []
    private(set) var remaining: String
    private(set) var columns: [CandidateColumn] = []
    /// 列ごとの、表示している先頭の候補の番号。
    private var pageStarts: [Int] = []
    private let makeColumns: (String) -> [CandidateColumn]

    init(reading: String, makeColumns: @escaping (String) -> [CandidateColumn]) {
        remaining = reading
        self.makeColumns = makeColumns
        refreshColumns()
    }

    var isFinished: Bool { remaining.isEmpty }
    var convertedText: String { selections.map(\.surface).joined() }
    /// 送信する文字列。変換していない残りの読みは、かなのまま付ける。
    var commitText: String { convertedText + remaining }

    func visibleCandidates(column: Int) -> ArraySlice<Candidate> {
        let candidates = columns[column].candidates
        let start = pageStarts[column]
        return candidates[start..<min(start + Self.pageSize(column: column), candidates.count)]
    }

    func hasNextPage(column: Int) -> Bool {
        columns[column].candidates.count > Self.pageSize(column: column)
    }

    /// 次の候補を表示する。最後まで行くと先頭に戻る。
    mutating func nextPage(column: Int) {
        let next = pageStarts[column] + Self.pageSize(column: column)
        pageStarts[column] = next < columns[column].candidates.count ? next : 0
    }

    mutating func select(column: Int, candidate: Candidate) {
        let reading = columns[column].reading
        selections.append(Selection(reading: reading, surface: candidate.surface))
        remaining.removeFirst(reading.count)
        refreshColumns()
    }

    /// 直前の選択を1つ戻す。戻す選択がなければ false。
    mutating func undo() -> Bool {
        guard let last = selections.popLast() else { return false }
        remaining = last.reading + remaining
        refreshColumns()
        return true
    }

    private mutating func refreshColumns() {
        columns = remaining.isEmpty ? [] : makeColumns(remaining)
        pageStarts = Array(repeating: 0, count: columns.count)
    }
}
