import Foundation
import DigiFinderCore

/// "What's around?" (§5.9): one offline answer from signs + YOLO + LiDAR, up to 5 things, nearest first, grouped by
/// type, with clock directions. "Checkout sign at 2 o'clock. Two people ahead. Shelves on both sides."
enum PerceptionSurroundings {
    static let maxItems = 5
    static let personLabels: Set<String> = ["Person", "Man", "Woman", "Boy", "Girl"]
    /// Labels that add nothing to a spoken overview.
    static let skipLabels: Set<String> = [
        "Human face", "Human body", "Human hair", "Human head", "Human arm", "Human hand", "Human leg", "Human foot",
        "Human nose", "Human eye", "Human mouth", "Human ear", "Human beard", "Clothing", "Footwear", "Furniture",
        "Fashion accessory", "Shelf", "Door", "Door handle", "Window", "Food", "Tableware", "Plant", "Houseplant",
    ]

    private struct Item { var text: String; var distance: Double }

    static func describe(signs: [PerceptionSign], detections: [Detection], geometry: PerceptionFrameGeometry?,
                         depthAt: (NormPoint) -> Float?) -> String {
        func clock(_ x: Double) -> Int { geometry?.clock(x) ?? clockPosition(portraitX: x, horizontalFOV: 80) }
        func place(_ x: Double) -> String {
            let c = clock(x)
            return c == 12 ? "ahead" : "at \(clockPhrase(c))"
        }
        func distance(_ box: NormRect, height: Double) -> Double {
            if let d = depthAt(box.center), d > 0 { return Double(d) }
            if let d = geometry?.distance(boxHeight: box.height, objectHeight: height) { return Double(d) }
            return height / max(box.height, 0.05)
        }

        var items: [Item] = []

        // Signs.
        var seenSigns = Set<String>()
        for s in signs where seenSigns.insert(s.key).inserted {
            let name: String
            switch s.destination {
            case .checkout?: name = "Checkout"
            case .customerService?: name = "Customer service"
            case nil: name = s.sign.number.map { "Aisle \($0)" } ?? (s.sign.words.first ?? "A")
            }
            items.append(Item(text: "\(name) sign \(place(s.box.midX))", distance: distance(s.box, height: s.lineHeight > 0 ? 0.12 * s.box.height / s.lineHeight : 0.3)))
        }

        let confident = detections.filter { $0.confidence >= 0.4 }

        // People (one count, nearest direction).
        let people = dedupe(confident.filter { personLabels.contains($0.label) })
        if let nearest = people.min(by: { distance($0.box, height: 1.7) < distance($1.box, height: 1.7) }) {
            let n = people.count
            let text = n == 1 ? "A person \(place(nearest.box.midX))" : "\(number(n).capitalizedFirst) people \(place(nearest.box.midX))"
            items.append(Item(text: text, distance: distance(nearest.box, height: 1.7)))
        }

        // Shelves by side.
        let shelves = confident.filter { $0.label == "Shelf" }
        if !shelves.isEmpty {
            let left = shelves.contains { $0.box.midX < 0.4 }, right = shelves.contains { $0.box.midX > 0.6 }
            let text = left && right ? "Shelves on both sides" : left ? "Shelves on your left" : right ? "Shelves on your right" : "Shelf ahead"
            let d = shelves.map { distance($0.box, height: 1.8) }.min() ?? 3
            items.append(Item(text: text, distance: d))
        }

        // Doors.
        let doors = dedupe(confident.filter { $0.label == "Door" })
        if let nearest = doors.min(by: { distance($0.box, height: 2.1) < distance($1.box, height: 2.1) }) {
            let text = doors.count == 1 ? "Door \(place(nearest.box.midX))" : "\(number(doors.count).capitalizedFirst) doors, nearest \(place(nearest.box.midX))"
            items.append(Item(text: text, distance: distance(nearest.box, height: 2.1)))
        }

        // Everything else, grouped by label.
        var groups: [String: [Detection]] = [:]
        for d in confident where d.confidence >= 0.5 && !personLabels.contains(d.label) && !skipLabels.contains(d.label) {
            groups[d.label, default: []].append(d)
        }
        for (label, ds) in groups {
            let group = dedupe(ds)
            guard let nearest = group.min(by: { distance($0.box, height: 1) < distance($1.box, height: 1) }) else { continue }
            let noun = label.lowercased()
            let text = group.count == 1
                ? "\(article(noun).capitalizedFirst) \(noun) \(place(nearest.box.midX))"
                : "\(number(group.count).capitalizedFirst) \(plural(noun)) \(place(nearest.box.midX))"
            items.append(Item(text: text, distance: distance(nearest.box, height: 1)))
        }

        guard !items.isEmpty else { return "I don't see much right now." }
        return items.sorted { $0.distance < $1.distance }.prefix(maxItems).map { $0.text + "." }.joined(separator: " ")
    }

    private static func dedupe(_ ds: [Detection]) -> [Detection] {
        var out: [Detection] = []
        for d in ds.sorted(by: { $0.confidence > $1.confidence }) where !out.contains(where: { $0.box.iou(d.box) > 0.5 }) {
            out.append(d)
        }
        return out
    }

    static func number(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return n < words.count ? words[n] : String(n)
    }

    private static func article(_ noun: String) -> String { "aeiou".contains(noun.first ?? "x") ? "an" : "a" }

    private static func plural(_ noun: String) -> String {
        if noun.hasSuffix("s") || noun.hasSuffix("x") || noun.hasSuffix("ch") || noun.hasSuffix("sh") { return noun + "es" }
        if noun.hasSuffix("y"), let c = noun.dropLast().last, !"aeiou".contains(c) { return noun.dropLast() + "ies" }
        return noun + "s"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
