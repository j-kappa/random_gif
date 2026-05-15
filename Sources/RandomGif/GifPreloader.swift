import Foundation

/// Fetches and caches the next GIF in the background so the window can
/// display it immediately without waiting for a network round-trip.
actor GifPreloader {
    static let shared = GifPreloader()

    private var preloaded: (url: URL, data: Data)?
    private var isLoading = false

    /// Begin a background fetch if one isn't already running.
    func kickoff() {
        guard !isLoading, preloaded == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            guard
                let url  = try? await GifFetcher.fetchRandomGifURL(),
                let data = try? await GifFetcher.fetchGifData(from: url)
            else { return }
            preloaded = (url, data)
        }
    }

    /// Returns the preloaded item (if ready) and immediately starts loading
    /// the next one. Returns nil if nothing is ready yet.
    func consume() -> (url: URL, data: Data)? {
        let item = preloaded
        preloaded = nil
        kickoff()          // start the next fetch right away
        return item
    }

    var isReady: Bool { preloaded != nil }
}
