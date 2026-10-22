import Foundation

/// Where optional snore clips live: Application Support/Clips, excluded from iCloud backup
/// so they stay on this device.
enum ClipStore {
    static var directory: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Clips", directoryHint: .isDirectory)
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var excluded = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
        }
        return directory
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// The clip's URL if the file exists.
    static func existingURL(for fileName: String?) -> URL? {
        guard let fileName else { return nil }
        let clipURL = url(for: fileName)
        return FileManager.default.fileExists(atPath: clipURL.path(percentEncoded: false)) ? clipURL : nil
    }

    static func delete(_ fileNames: [String]) {
        for name in fileNames {
            try? FileManager.default.removeItem(at: url(for: name))
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
