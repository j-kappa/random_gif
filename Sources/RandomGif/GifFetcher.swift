import Foundation

enum GifFetchError: Error {
    case noGifFound
}

enum GifFetcher {

    // MARK: - Public

    static func fetchRandomGifURL() async throws -> URL {
        // Give reddit more weight since it covers the most variety
        let pool: [() async throws -> URL] = [
            fetchFromReddit,
            fetchFromReddit,
            fetchFromReddit,
            fetchFromDogAPI,
            fetchFromCatAPI,
        ]

        for fetcher in pool.shuffled() {
            if let url = try? await fetcher() {
                return url
            }
        }
        throw GifFetchError.noGifFound
    }

    static func fetchGifData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw GifFetchError.noGifFound
        }
        return data
    }

    // MARK: - Sources

    private static func fetchFromReddit() async throws -> URL {
        let subreddits = [
            "gifs", "reactiongifs", "wholesomegifs",
            "AnimalsBeingGifs", "aww", "funny",
            "meirl", "mildlyinteresting"
        ]
        let sub = subreddits.randomElement()!
        let apiURL = URL(string: "https://www.reddit.com/r/\(sub)/hot.json?limit=75")!

        var request = URLRequest(url: apiURL)
        request.setValue("RandomGifMacApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GifFetchError.noGifFound
        }

        struct Post: Decodable { let url: String; let is_video: Bool }
        struct Child: Decodable { let data: Post }
        struct Listing: Decodable { let children: [Child] }
        struct Root: Decodable { let data: Listing }

        let root = try JSONDecoder().decode(Root.self, from: data)
        let posts = root.data.children.map(\.data)

        // Accept direct .gif or imgur .gifv links (convert .gifv → .gif)
        let candidates: [String] = posts.compactMap { post in
            guard !post.is_video else { return nil }
            let u = post.url
            if u.hasSuffix(".gif") { return u }
            if u.hasSuffix(".gifv") && u.contains("i.imgur.com") {
                return u.replacingOccurrences(of: ".gifv", with: ".gif")
            }
            return nil
        }

        guard let urlString = candidates.randomElement(),
              let url = URL(string: urlString) else {
            throw GifFetchError.noGifFound
        }
        return url
    }

    private static func fetchFromDogAPI() async throws -> URL {
        struct Response: Decodable { let url: String }

        for _ in 0..<5 {
            let api = URL(string: "https://random.dog/woof.json")!
            let (data, _) = try await URLSession.shared.data(from: api)
            let r = try JSONDecoder().decode(Response.self, from: data)
            if r.url.hasSuffix(".gif"), let url = URL(string: r.url) {
                return url
            }
        }
        throw GifFetchError.noGifFound
    }

    private static func fetchFromCatAPI() async throws -> URL {
        struct Cat: Decodable { let url: String }

        let api = URL(string: "https://api.thecatapi.com/v1/images/search?mime_types=gif&limit=1")!
        let (data, _) = try await URLSession.shared.data(from: api)
        let cats = try JSONDecoder().decode([Cat].self, from: data)

        guard let first = cats.first, let url = URL(string: first.url) else {
            throw GifFetchError.noGifFound
        }
        return url
    }
}
