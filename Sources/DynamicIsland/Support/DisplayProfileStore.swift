import Foundation
import DynamicIslandCore

struct DisplayProfileStore: Sendable {
    static let defaultProfileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dynamic Island", isDirectory: true)
        .appendingPathComponent("display-profile.json")
    static let legacyProfileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Island", isDirectory: true)
        .appendingPathComponent("display-profile.json")

    let profileURL: URL

    init(profileURL: URL = Self.defaultProfileURL) {
        self.profileURL = profileURL
    }

    func cachedProfile(matching signature: DisplaySignature) -> DisplayProfile? {
        guard let profile = loadProfile(), profile.matches(signature) else {
            return nil
        }
        return profile
    }

    func save(_ profile: DisplayProfile) {
        do {
            try FileManager.default.createDirectory(
                at: profileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profile)
            try data.write(to: profileURL, options: [.atomic])
        } catch {
            return
        }
    }

    private func loadProfile() -> DisplayProfile? {
        if let data = try? Data(contentsOf: profileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(DisplayProfile.self, from: data)
        }

        guard profileURL == Self.defaultProfileURL || profileURL == Self.legacyProfileURL else {
            return nil
        }

        guard let data = try? Data(contentsOf: Self.legacyProfileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DisplayProfile.self, from: data)
    }
}
