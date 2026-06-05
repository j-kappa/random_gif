import AppKit
import UniformTypeIdentifiers

/// Shares GIFs via a stable file reference on the pasteboard.
///
/// Slack and Twitter are Electron/Chromium apps. Raw GIF bytes get flattened to
/// PNG on paste; a file reference (without image data) preserves the animation.
/// The file lives in the app cache, not the user's Downloads folder.
enum GifClipboard {
    private static let filename = "RandomGif.gif"

    static var shareURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.randomgif.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    @discardableResult
    static func writeShareFile(data: Data) -> URL? {
        let url = shareURL
        guard (try? data.write(to: url, options: .atomic)) != nil else {
            return nil
        }
        return url
    }

    @discardableResult
    static func copy(data: Data) -> URL? {
        guard let url = writeShareFile(data: data) else { return nil }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        return url
    }

    static func cleanup() {
        try? FileManager.default.removeItem(at: shareURL)
    }
}
