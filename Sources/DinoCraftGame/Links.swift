import Foundation
import DinoCraftCore

/// Web links shown in the launcher (Resources/Data/links.json). An empty link hides its button.
enum GameLinks {
    private struct File: Decodable { var donate: String?; var donateLabel: String?; var reviewsRepo: String? }

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
}
