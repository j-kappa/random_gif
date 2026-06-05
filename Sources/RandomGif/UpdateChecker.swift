import Foundation
import AppKit

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "j-kappa"
    private let repoName  = "random_gif"
    private let releasesPage = URL(string: "https://github.com/j-kappa/random_gif/releases")!

    private(set) var latestVersion: String? = nil
    var onUpdateAvailable: ((String) -> Void)?

    private init() {}

    /// Checks GitHub for a newer release. Calls `onUpdateAvailable` on the main thread
    /// if a newer version is found. Safe to call multiple times; subsequent calls after
    /// the first successful check are no-ops.
    func checkInBackground() {
        Task.detached(priority: .background) { [weak self] in
            await self?.fetchLatestRelease()
        }
    }

    // MARK: - Private

    private func fetchLatestRelease() async {
        let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Use the bundle version as a courteous User-Agent
        let currentVersion = Bundle.main.shortVersion ?? "unknown"
        request.setValue("RandomGif/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String
        else { return }

        let remote = Self.normalise(tagName)
        let local  = Self.normalise(currentVersion)

        guard Self.isNewer(remote, than: local) else { return }

        await MainActor.run { [weak self] in
            self?.latestVersion = remote
            self?.onUpdateAvailable?(remote)
        }
    }

    /// Strips a leading "v" and returns the version string.
    private static func normalise(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    /// Compares two dot-separated version strings, e.g. "1.2.0" > "1.1.9".
    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents  = local.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(remoteComponents.count, localComponents.count)
        for i in 0..<maxLen {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let l = i < localComponents.count  ? localComponents[i]  : 0
            if r != l { return r > l }
        }
        return false
    }

    /// Opens the GitHub releases page in the default browser.
    func openReleasesPage() {
        NSWorkspace.shared.open(releasesPage)
    }
}

private extension Bundle {
    var shortVersion: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
