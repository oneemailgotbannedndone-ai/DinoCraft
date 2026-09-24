import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One player review: a star rating and a few words.
public struct GameReview: Sendable, Equatable {
    public var author: String
    public var stars: Int
    public var text: String
    public var date: String
}

/// Global reviews, shared by every player on every computer. They live as issues titled
/// "Review: ★★★★☆" on the public releases repository: the launcher reads them from GitHub's
/// public API (no account needed) and "Write a Review" opens a pre-filled GitHub page.
public final class ReviewBoard: @unchecked Sendable {
    public enum State: Sendable {
        case idle
        case loading
        case loaded([GameReview])
        case failed(String)
    }

    public let repository: String
    private let lock = NSLock()
    private var _state = State.idle

    public init(repository: String) {
        self.repository = repository
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    private func set(_ s: State) {
        lock.lock(); _state = s; lock.unlock()
    }

    public var reviews: [GameReview] {
        if case .loaded(let list) = state { return list }
        return []
    }

    /// Average stars (0 when there are no reviews yet).
    public var average: Double {
        let list = reviews
        return list.isEmpty ? 0 : Double(list.reduce(0) { $0 + $1.stars }) / Double(list.count)
    }

    public func load() {
        if case .loading = state { return }
        set(.loading)
        // DINOCRAFT_REVIEWS_URL points at a test server instead of GitHub.
        let address = ProcessInfo.processInfo.environment["DINOCRAFT_REVIEWS_URL"]
            ?? "https://api.github.com/repos/\(repository)/issues?state=all&per_page=100"
        guard let url = URL(string: address) else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DinoCraft-Launcher", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil {
                self.set(.failed("Couldn't reach the reviews. Check your internet connection."))
            } else if status == 404 {
                self.set(.failed("Reviews open once the public DinoCraft-Releases page is set up."))
            } else if status == 403 || status == 429 {
                self.set(.failed("GitHub is busy right now. Try again in a little while."))
            } else if status == 200, let data {
                self.set(.loaded(ReviewBoard.parse(data)))
            } else {
                self.set(.failed("The reviews couldn't be loaded (HTTP \(status))."))
            }
        }.resume()
    }

    /// Reads GitHub issues, keeping those titled like "Review: ★★★★☆" or "Review: 4/5".
    public static func parse(_ data: Data) -> [GameReview] {
        struct Issue: Decodable {
            struct User: Decodable { let login: String }
            let title: String
            let body: String?
            let user: User
            let created_at: String
            let pull_request: [String: String?]?
        }
        guard let issues = try? JSONDecoder().decode([Issue].self, from: data) else { return [] }
        return issues.compactMap { issue in
            guard issue.pull_request == nil, issue.title.lowercased().hasPrefix("review") else { return nil }
            var stars = issue.title.filter { $0 == "\u{2605}" }.count
            if stars == 0, let digit = issue.title.first(where: { ("1"..."5").contains($0) }) { stars = Int(String(digit)) ?? 0 }
            guard (1...5).contains(stars) else { return nil }
            var text = (issue.body ?? "").replacingOccurrences(of: "Write what you think of DinoCraft here!", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let cut = text.range(of: "\n---") { text = String(text[..<cut.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
            if text.count > 280 { text = String(text.prefix(279)) + "\u{2026}" }
            return GameReview(author: issue.user.login, stars: stars, text: text.isEmpty ? "(no words, just stars)" : text,
                              date: String(issue.created_at.prefix(10)))
        }
    }

    /// The GitHub page for posting a review with `stars`, pre-filled so players only type their words.
    public func writeURL(stars: Int, username: String) -> URL? {
        let rating = String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 5 - stars)
        let body = "Write what you think of DinoCraft here!\n\n---\nPlayer name in game: \(username.isEmpty ? "?" : username)"
        var parts = URLComponents(string: "https://github.com/\(repository)/issues/new")
        parts?.queryItems = [URLQueryItem(name: "title", value: "Review: \(rating)"), URLQueryItem(name: "body", value: body)]
        return parts?.url
    }
}
