import Foundation

struct SubtitleStabilizer {
    private var lastDisplayed = ""
    private var pending = ""
    private var pendingMatches = 0

    mutating func ingest(_ candidate: String) -> String? {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.words(in: candidate).count >= 2 else { return nil }

        // A rolling audio window keeps producing small rewrites of the same
        // thought. Once shown, keep that subtitle fixed until genuinely new
        // speech replaces it.
        if !lastDisplayed.isEmpty,
           Self.similarity(candidate, lastDisplayed) >= 0.55 {
            pending = ""
            pendingMatches = 0
            return nil
        }

        if !pending.isEmpty, Self.similarity(candidate, pending) >= 0.55 {
            pending = candidate
            pendingMatches += 1
        } else {
            pending = candidate
            pendingMatches = 1
        }

        // Two consecutive interpretations provide a short, deterministic
        // confirmation delay without waiting for a long silence.
        guard pendingMatches >= 2 else { return nil }
        lastDisplayed = candidate
        pending = ""
        pendingMatches = 0
        return candidate
    }

    mutating func reset() {
        lastDisplayed = ""
        pending = ""
        pendingMatches = 0
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(words(in: lhs))
        let right = Set(words(in: rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let common = left.intersection(right).count
        return (2 * Double(common)) / Double(left.count + right.count)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
