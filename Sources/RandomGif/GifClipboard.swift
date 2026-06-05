import AppKit
import UniformTypeIdentifiers

/// Copies a GIF to the system pasteboard using two items so different apps
/// pick the representation they understand:
///   - File item → Slack desktop (uploads RandomGif.gif, keeps animation)
///   - Data item → browsers like Twitter/X (reads image/gif bytes on paste)
enum GifClipboard {
    private static let filename = "RandomGif.gif"
    private static var keptFileURL: URL?

    @discardableResult
    static func copy(data: Data) -> Bool {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        guard (try? data.write(to: tempURL, options: .atomic)) != nil else {
            return false
        }

        if let old = keptFileURL, old != tempURL {
            try? FileManager.default.removeItem(at: old)
        }
        keptFileURL = tempURL

        let gifType = NSPasteboard.PasteboardType(UTType.gif.identifier)

        // Item 1: file reference — native apps upload this as RandomGif.gif
        let fileItem = NSPasteboardItem()
        fileItem.setData(tempURL.dataRepresentation, forType: .fileURL)
        fileItem.setPropertyList([tempURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))

        // Item 2: raw GIF bytes — browsers read this as image/gif on paste
        let dataItem = NSPasteboardItem()
        dataItem.setData(data, forType: gifType)
        dataItem.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileItem, dataItem])

        return true
    }

    static func cleanup() {
        if let url = keptFileURL {
            try? FileManager.default.removeItem(at: url)
            keptFileURL = nil
        }
    }
}
