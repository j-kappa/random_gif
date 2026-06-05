import AppKit
import UniformTypeIdentifiers

/// Clipboard and drag helpers for sharing GIFs.
///
/// Paste  → raw GIF bytes only (works in Twitter/X and avoids Slack's file-upload
///          rejection dialog; Slack may show a static preview when pasting).
/// Drag   → RandomGif.gif file (works in Slack desktop for animated GIFs).
enum GifClipboard {
    private static let filename = "RandomGif.gif"
    private static var keptFileURL: URL?

    /// Writes the GIF to a stable temp path for drag-and-drop.
    static func fileURL(for data: Data) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        guard (try? data.write(to: tempURL, options: .atomic)) != nil else {
            return nil
        }

        if let old = keptFileURL, old != tempURL {
            try? FileManager.default.removeItem(at: old)
        }
        keptFileURL = tempURL
        return tempURL
    }

    /// Copies GIF bytes to the pasteboard — no file references.
    @discardableResult
    static func copy(data: Data) -> Bool {
        let gifType = NSPasteboard.PasteboardType(UTType.gif.identifier)

        let item = NSPasteboardItem()
        item.setData(data, forType: gifType)
        item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
        return true
    }

    static func cleanup() {
        if let url = keptFileURL {
            try? FileManager.default.removeItem(at: url)
            keptFileURL = nil
        }
    }
}
