import Foundation
import SwiftData

@Model
final class PersistedClipItem {
    @Attribute(.unique) var id: UUID
    var date: Date
    var contentType: String  // "text" | "image" | "fileURLs"
    var textContent: String?
    @Attribute(.externalStorage) var imageData: Data?
    var fileURLsJSON: String?
    var sourceAppName: String?
    var sourceAppBundleID: String?

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
