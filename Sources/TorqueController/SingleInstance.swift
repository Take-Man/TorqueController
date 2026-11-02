import AppKit

/// 二重起動の判定。別の場所にある同じアプリや、実行ファイルの直接起動でも、キー入力を送るプロセスを1つにする。
enum SingleInstance {
    static let bundleIdentifier = "com.takeman.torquecontroller"

    struct Process: Equatable {
        let pid: pid_t
        let launchDate: Date?

        /// 起動時刻で比べ、分からないか同じならプロセスIDで比べる。どの2つでも必ず片方だけが先になる。
        func startedBefore(_ other: Process) -> Bool {
            if let launchDate, let otherDate = other.launchDate, launchDate != otherDate {
                return launchDate < otherDate
            }
            return pid < other.pid
        }
    }

    /// own より先に動いている別のプロセスがあれば true。同時に起動しても、最も古い1つだけが残る。
    static func isDuplicate(own: Process, running: [Process]) -> Bool {
        running.contains { $0.pid != own.pid && $0.startedBefore(own) }
    }

    /// 今のプロセスが、すでに動いているものの重複か。
    static func isDuplicateOfRunningProcess() -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map { Process(pid: $0.processIdentifier, launchDate: $0.launchDate) }
        let own = Process(pid: ProcessInfo.processInfo.processIdentifier, launchDate: NSRunningApplication.current.launchDate)
        return isDuplicate(own: own, running: running)
    }
}
