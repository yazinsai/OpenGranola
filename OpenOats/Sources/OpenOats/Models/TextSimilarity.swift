import Foundation

enum TextSimilarity {
    static func normalizedWords(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func normalizedText(_ text: String) -> String {
        normalizedWords(in: text).joined(separator: " ")
    }

    static func jaccard(_ a: String, _ b: String) -> Double {
        let setA = Set(normalizedWords(in: a))
        let setB = Set(normalizedWords(in: b))
        guard !setA.isEmpty || !setB.isEmpty else { return 1.0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }
}
