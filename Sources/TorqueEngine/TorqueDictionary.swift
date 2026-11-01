import Foundation

/// 読みでソートしたバイナリ辞書。メモリマップで読み、読みの完全一致を二分探索で引く。
///
/// 形式(リトルエンディアン): ヘッダー 24 バイト、ID ごとの付属語の印、読みの表(文字列位置、長さ、最初の語の番号)、
/// 語の表(表記の位置、表記の長さ、左ID、右ID、コスト)、文字列、接続コスト(N×N 個の Int16)。
public final class TorqueDictionary: @unchecked Sendable {
    public enum LoadError: Error, CustomStringConvertible {
        case cannotOpen(String)
        case invalidFormat

        public var description: String {
            switch self {
            case .cannotOpen(let path): "辞書を開けません: \(path)"
            case .invalidFormat: "辞書の形式が違います"
            }
        }
    }

    static let magic: UInt32 = 0x3144_5154 // "TQD1"
    private static let headerSize = 24
    private static let readingRecordSize = 12
    private static let entryRecordSize = 12

    /// 辞書の1語。
    struct Entry {
        let surfaceOffset: UInt32
        let surfaceLength: UInt16
        let leftID: UInt16
        let rightID: UInt16
        let cost: Int16
    }

    private let base: UnsafeRawPointer
    private let byteCount: Int
    private let readingCount: Int
    private let entryCount: Int
    private let functionalFlags: UnsafeRawPointer
    private let readingTable: UnsafeRawPointer
    private let entryTable: UnsafeRawPointer
    private let strings: UnsafeRawPointer
    private let connection: UnsafeRawPointer
    let idCount: Int
    let unknownID: UInt16

    public init(contentsOf url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw LoadError.cannotOpen(url.path) }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_size >= Self.headerSize,
              let mapped = mmap(nil, Int(status.st_size), PROT_READ, MAP_PRIVATE, descriptor, 0),
              mapped != MAP_FAILED
        else { throw LoadError.cannotOpen(url.path) }

        let base = UnsafeRawPointer(mapped)
        let size = Int(status.st_size)
        let header = { (index: Int) in base.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self).littleEndian }
        let readingCount = Int(header(1))
        let entryCount = Int(header(2))
        let stringsSize = Int(header(3))
        let idCount = Int(header(4))

        var offset = Self.headerSize
        let flagsOffset = offset
        offset += idCount
        offset = (offset + 3) / 4 * 4
        let readingOffset = offset
        offset += (readingCount + 1) * Self.readingRecordSize
        let entryOffset = offset
        offset += entryCount * Self.entryRecordSize
        let stringsOffset = offset
        offset += stringsSize
        offset = (offset + 1) / 2 * 2
        let connectionOffset = offset
        offset += idCount * idCount * 2

        guard header(0) == Self.magic, offset == size else {
            munmap(mapped, size)
            throw LoadError.invalidFormat
        }

        self.base = base
        byteCount = size
        self.readingCount = readingCount
        self.entryCount = entryCount
        self.idCount = idCount
        unknownID = UInt16(header(5))
        functionalFlags = base + flagsOffset
        readingTable = base + readingOffset
        entryTable = base + entryOffset
        strings = base + stringsOffset
        connection = base + connectionOffset
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: base), byteCount)
    }

    /// 読みに完全一致する語の番号の範囲。なければ空の範囲。
    func entries(forReading reading: UnsafeBufferPointer<UInt8>) -> Range<Int> {
        var low = 0
        var high = readingCount
        while low < high {
            let middle = (low + high) / 2
            let order = compareReading(at: middle, to: reading)
            if order == 0 {
                return firstEntry(ofReading: middle)..<firstEntry(ofReading: middle + 1)
            }
            if order < 0 {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return 0..<0
    }

    func entry(at index: Int) -> Entry {
        let pointer = entryTable + index * Self.entryRecordSize
        return Entry(
            surfaceOffset: pointer.loadUnaligned(as: UInt32.self).littleEndian,
            surfaceLength: pointer.loadUnaligned(fromByteOffset: 4, as: UInt16.self).littleEndian,
            leftID: pointer.loadUnaligned(fromByteOffset: 6, as: UInt16.self).littleEndian,
            rightID: pointer.loadUnaligned(fromByteOffset: 8, as: UInt16.self).littleEndian,
            cost: Int16(bitPattern: pointer.loadUnaligned(fromByteOffset: 10, as: UInt16.self).littleEndian)
        )
    }

    func surface(of entry: Entry) -> String {
        let bytes = UnsafeRawBufferPointer(start: strings + Int(entry.surfaceOffset), count: Int(entry.surfaceLength))
        return String(decoding: bytes, as: UTF8.self)
    }

    func isFunctional(id: UInt16) -> Bool {
        functionalFlags.load(fromByteOffset: Int(id), as: UInt8.self) != 0
    }

    /// 左の語の右ID と右の語の左ID の接続コスト。
    func connectionCost(right: UInt16, left: UInt16) -> Int {
        let index = Int(right) * idCount + Int(left)
        return Int(Int16(bitPattern: connection.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self).littleEndian))
    }

    private func firstEntry(ofReading index: Int) -> Int {
        Int(readingTable.loadUnaligned(fromByteOffset: index * Self.readingRecordSize + 8, as: UInt32.self).littleEndian)
    }

    private func compareReading(at index: Int, to target: UnsafeBufferPointer<UInt8>) -> Int {
        let record = readingTable + index * Self.readingRecordSize
        let offset = Int(record.loadUnaligned(as: UInt32.self).littleEndian)
        let length = Int(record.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian)
        let order = memcmp(strings + offset, target.baseAddress, min(length, target.count))
        if order != 0 { return Int(order) }
        return length - target.count
    }
}
