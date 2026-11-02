import Foundation
import Testing
@testable import TorqueController

private let early = Date(timeIntervalSince1970: 1000)
private let late = Date(timeIntervalSince1970: 2000)

@Test func aloneIsNotDuplicate() {
    let own = SingleInstance.Process(pid: 200, launchDate: late)
    #expect(!SingleInstance.isDuplicate(own: own, running: []))
    #expect(!SingleInstance.isDuplicate(own: own, running: [own]))
}

@Test func newerProcessIsDuplicateAndOlderStays() {
    // プロセスIDが巡回して、古い方が大きくなっていても起動時刻を優先する
    let older = SingleInstance.Process(pid: 900, launchDate: early)
    let newer = SingleInstance.Process(pid: 100, launchDate: late)
    #expect(SingleInstance.isDuplicate(own: newer, running: [older, newer]))
    #expect(!SingleInstance.isDuplicate(own: older, running: [older, newer]))
}

@Test(arguments: [(early, early), (nil, early), (early, nil), (nil, nil)] as [(Date?, Date?)])
func sameOrUnknownLaunchDateLeavesExactlyOne(first: Date?, second: Date?) {
    let a = SingleInstance.Process(pid: 100, launchDate: first)
    let b = SingleInstance.Process(pid: 200, launchDate: second)
    #expect(!SingleInstance.isDuplicate(own: a, running: [a, b]))
    #expect(SingleInstance.isDuplicate(own: b, running: [a, b]))
}

@Test func onlyOldestOfManySurvives() {
    let processes = [
        SingleInstance.Process(pid: 300, launchDate: late),
        SingleInstance.Process(pid: 100, launchDate: early),
        SingleInstance.Process(pid: 200, launchDate: late),
    ]
    let survivors = processes.filter { !SingleInstance.isDuplicate(own: $0, running: processes) }
    #expect(survivors.map(\.pid) == [100])
}
