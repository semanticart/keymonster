import Foundation
import GRDB

/// One persisted clipboard row. Mirrors the columns of the `clipItem` table;
/// `ClipItem` is the in-memory/UI form and converts to and from this.
struct ClipRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    var id: UUID
    var date: Date
    var contentType: String  // "text" | "image" | "fileURLs"
    var textContent: String?
    var imageData: Data?
    var fileURLsJSON: String?
    var sourceAppName: String?
    var sourceAppBundleID: String?

    static let databaseTableName = "clipItem"

    init(
        id: UUID,
        date: Date,
        contentType: String,
        textContent: String? = nil,
        imageData: Data? = nil,
        fileURLsJSON: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.date = date
        self.contentType = contentType
        self.textContent = textContent
        self.imageData = imageData
        self.fileURLsJSON = fileURLsJSON
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
    }
}

/// Persistence boundary for clipboard history, kept narrow so `ClipboardHistory`
/// can be tested against an in-memory store (see `SQLiteClipStore.inMemory()`).
protocol ClipStore: Sendable {
    func load() throws -> [ClipRecord]
    func insert(_ record: ClipRecord) throws
    func delete(id: UUID) throws
    func deleteAll() throws
}

/// SQLite-backed `ClipStore` using GRDB. Unlike SwiftData this works the same
/// whether the process is a bare executable or a real `.app` bundle, so it has
/// no bundle-identifier requirement and is usable directly from tests.
final class SQLiteClipStore: ClipStore {
    private let dbQueue: DatabaseQueue

    init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrate()
    }

    convenience init(url: URL) throws {
        try self.init(DatabaseQueue(path: url.path))
    }

    /// An ephemeral, in-memory store for tests.
    static func inMemory() throws -> SQLiteClipStore {
        try SQLiteClipStore(DatabaseQueue())
    }

    /// The on-disk location of the user's history database, creating the
    /// containing directory if needed. Shared by the app and the snapshot tool
    /// so both read and write the same file.
    static func defaultURL() throws -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("clipborg")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createClipItem") { database in
            try database.create(table: ClipRecord.databaseTableName) { table in
                table.primaryKey("id", .blob)
                table.column("date", .datetime).notNull().indexed()
                table.column("contentType", .text).notNull()
                table.column("textContent", .text)
                table.column("imageData", .blob)
                table.column("fileURLsJSON", .text)
                table.column("sourceAppName", .text)
                table.column("sourceAppBundleID", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }

    func load() throws -> [ClipRecord] {
        try dbQueue.read { database in
            try ClipRecord.order(Column("date").desc).fetchAll(database)
        }
    }

    func insert(_ record: ClipRecord) throws {
        try dbQueue.write { database in try record.insert(database) }
    }

    func delete(id: UUID) throws {
        _ = try dbQueue.write { database in try ClipRecord.deleteOne(database, key: ["id": id]) }
    }

    func deleteAll() throws {
        _ = try dbQueue.write { database in try ClipRecord.deleteAll(database) }
    }
}
