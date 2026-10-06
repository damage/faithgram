import Foundation

public enum PatchClientStorage {
    public static func containerURL(sharedContainer: URL?, applicationSupport: URL? = nil, fileManager: FileManager = .default) throws -> URL {
        let container: URL
        if let sharedContainer = sharedContainer {
            container = sharedContainer
        } else {
            let support: URL
            if let applicationSupport = applicationSupport {
                support = applicationSupport
            } else {
                support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            }
            container = support.appendingPathComponent("Faithgram", isDirectory: true)
        }

        // The database key is written before the account manager starts.
        // Its parent directory must exist synchronously on the first launch.
        var dataDirectory = container.appendingPathComponent("telegram-data", isDirectory: true)
        #if os(iOS)
        let attributes: [FileAttributeKey: Any]? = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        let attributes: [FileAttributeKey: Any]? = nil
        #endif
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: attributes)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dataDirectory.setResourceValues(values)
        return container
    }
}
