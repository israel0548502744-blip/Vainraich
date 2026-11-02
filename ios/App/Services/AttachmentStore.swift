import Foundation
import UIKit

/// Stores transaction attachments (receipt photos, PDFs) in the app's private, encrypted container.
enum AttachmentStore {
    static var directory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    /// Saves data and returns the stored file name.
    static func save(_ data: Data, fileExtension: String) throws -> String {
        let name = UUID().uuidString + "." + fileExtension
        let url = url(for: name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }

    static func saveImage(_ image: UIImage) throws -> String {
        guard let jpeg = image.downscaled(maxDimension: 2000).jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try save(jpeg, fileExtension: "jpg")
    }

    static func image(_ fileName: String) -> UIImage? { UIImage(contentsOfFile: url(for: fileName).path) }

    static func delete(_ fileName: String) { try? FileManager.default.removeItem(at: url(for: fileName)) }

    static func deleteAll() { try? FileManager.default.removeItem(at: directory) }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
