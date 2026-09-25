import Foundation
import DinoCraftCore

/// Web links shown in the launcher (Resources/Data/links.json). An empty link hides its button.
enum GameLinks {
    private struct File: Decodable {
        var donate: String?; var donateLabel: String?; var reviewsRepo: String?
        var leaderboardPublic: String?; var leaderboardPrivate: String?
    }

    private static let file: File? = {
        guard let url = try? ResourceLocator.url("Data/links.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    /// Where the launcher's donate button goes (Ko-fi, PayPal, GitHub Sponsors...), or nil if not set up yet.
    static var donate: URL? {
        guard let text = file?.donate?.trimmingCharacters(in: .whitespaces), text.hasPrefix("https://") else { return nil }
        return URL(string: text)
    }

    static var donateLabel: String { file?.donateLabel ?? "Support DinoCraft" }

    /// The public repository whose issues hold everyone's reviews.
    static var reviewsRepo: String { file?.reviewsRepo ?? "oneemailgotbannedndone-ai/DinoCraft" }

    /// Shared by the launcher screens; loaded when the Reviews page opens.
    static let reviews = ReviewBoard(repository: reviewsRepo)

    /// The global stats leaderboard (a free dreamlo board: the public code reads it, the private one adds to it).
    static let leaderboard = Leaderboard(publicCode: file?.leaderboardPublic ?? "6ab5ea248f40bb15a8a09cf5",
                                         privateCode: file?.leaderboardPrivate ?? "UvOZfS-1XEOGjMNE1aEcvA3l8iiAnMH06ZW5MzVwZpOw")

    /// Shares this player's lifetime stats on the leaderboard whenever `PlayerStats` asks (call at startup).
    static func setUpStats(_ store: SettingsStore) {
        PlayerStats.shared.onSubmit = { values in
            leaderboard.submit(name: store.settings.username, playerID: store.settings.playerID, stats: values)
        }
    }
}
