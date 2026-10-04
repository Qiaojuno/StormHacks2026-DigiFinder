// Shelf vote (§5.7): labels and YOLO objects vote for an aisle, each once.

public struct AisleVote {
    public private(set) var counts: [String: Int] = [:]
    private var seen = Set<String>()
    public init() {}

    public mutating func addText(_ label: String, wordToAisle: [String: String]) {
        let key = normalizeText(label)
        guard !seen.contains(key), let a = wordToAisle.first(where: { key.contains($0.key) })?.value else { return }
        counts[a, default: 0] += 1; seen.insert(key)
    }

    public mutating func addVisual(trackID: Int, yoloClass: String, classToAisle: [String: String]) {
        let key = "yolo-\(trackID)"
        guard !seen.contains(key), let a = classToAisle[yoloClass] else { return }
        counts[a, default: 0] += 1; seen.insert(key)
    }

    public func verdict(minVotes: Int = 6, minShare: Double = 0.6) -> String? {
        let total = counts.values.reduce(0, +)
        guard total >= minVotes, let top = counts.max(by: { $0.value < $1.value }),
              Double(top.value) / Double(total) >= minShare else { return nil }
        return top.key
    }
}
