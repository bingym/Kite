import Foundation

public struct ProcessSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let name: String
    public let path: String?
    public let parentID: Int32
    public let userID: UInt32
    public let userName: String
    public let virtualMemory: UInt64
    public let residentMemory: UInt64
    public let memoryFootprint: UInt64
    public let threadCount: Int32
    public let startDate: Date?
    public let cpuTimeNanoseconds: UInt64
    public let cpuPercent: Double

    public init(
        id: Int32,
        name: String,
        path: String? = nil,
        parentID: Int32 = 0,
        userID: UInt32 = 0,
        userName: String = "root",
        virtualMemory: UInt64 = 0,
        residentMemory: UInt64 = 0,
        memoryFootprint: UInt64 = 0,
        threadCount: Int32 = 0,
        startDate: Date? = nil,
        cpuTimeNanoseconds: UInt64 = 0,
        cpuPercent: Double = 0
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.parentID = parentID
        self.userID = userID
        self.userName = userName
        self.virtualMemory = virtualMemory
        self.residentMemory = residentMemory
        self.memoryFootprint = memoryFootprint
        self.threadCount = threadCount
        self.startDate = startDate
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.cpuPercent = cpuPercent
    }
}
