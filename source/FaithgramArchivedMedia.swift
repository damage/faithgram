import Foundation
import Postbox
import SwiftSignalKit

enum FaithgramArchivedMedia {
    private static let queue = DispatchQueue(label: "faithgram.media.archive", qos: .utility)
    @available(iOS 13.4, *)
    private static func archive(_ mediaBox: MediaBox) throws -> FaithgramMediaArchive {
        let root = URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent()
        let key = try FaithgramVault.accountKey("media:" + root.deletingLastPathComponent().lastPathComponent)
        return try FaithgramMediaArchive(directory: root.appendingPathComponent("faithgram-media", isDirectory: true), key: key)
    }
    static func capture(_ message: Message, mediaBox: MediaBox) {
        guard #available(iOS 13.4, *) else { return }
        guard PatchClientPolicy.isEnabled(.archiveDownloadedMedia),
              message.autoremoveAttribute == nil, message.autoclearAttribute == nil,
              message.id.peerId.namespace != Namespaces.Peer.SecretChat,
              FaithgramPreferences.mediaRules[String(message.id.peerId.toInt64())] != false else { return }
        var resources: [MediaResource] = []
        for media in message.media {
            if let image = media as? TelegramMediaImage { resources += image.representations.map { $0.resource } }
            if let file = media as? TelegramMediaFile { resources.append(file.resource); resources += file.previewRepresentations.map { $0.resource } }
        }
        let paths = resources.compactMap { resource -> (String, URL)? in
            guard let path = mediaBox.completedResourcePath(resource) else { return nil }
            return (resource.id.stringRepresentation, URL(fileURLWithPath: path))
        }
        queue.async {
            do {
                let archive = try archive(mediaBox)
                for (resource, path) in paths where FileManager.default.fileExists(atPath: path.path) { try archive.save(resource: resource, source: path) }
            } catch { FaithgramPreferences.setText("historyError", "Downloaded media could not be archived. Check available storage and device access.") }
        }
    }
    static func restore(mediaBox: MediaBox, resource: MediaResource) -> Signal<Void, FetchResourceError> {
        guard #available(iOS 13.4, *) else { return .single(()) }
        let root = URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("faithgram-media").path), mediaBox.completedResourcePath(resource) == nil else { return .single(()) }
        return Signal { subscriber in
            queue.async {
                if mediaBox.completedResourcePath(resource) == nil {
                    do {
                        let destination = URL(fileURLWithPath: mediaBox.storePathsForId(resource.id).complete)
                        let _ = try archive(mediaBox).restore(resource: resource.id.stringRepresentation, destination: destination)
                    } catch { FaithgramPreferences.setText("historyError", "Archived media could not be opened. The archive may be damaged or unavailable.") }
                }
                subscriber.putNext(())
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
}
