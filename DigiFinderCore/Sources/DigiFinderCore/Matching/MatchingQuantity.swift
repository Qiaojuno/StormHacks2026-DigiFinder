import Foundation

// Package sizes: parse "340 g", "1.36 kg", "12 oz (340 g)", "6 x 355 mL", "24 ct"; compare across units;
// speak them ("340 grams", "a 680 gram one").

public struct MatchingQuantity: Equatable {
    public enum Unit: String, Equatable { case gram, kilogram, milliliter, liter, ounce, fluidOunce, pound, count }
    public enum Family: Equatable { case mass, volume, count }

    public var value: Double
    public var unit: Unit
    /// "6 x 355 mL" → 6.
    public var packCount: Int?

    public init(value: Double, unit: Unit, packCount: Int? = nil) {
        self.value = value; self.unit = unit; self.packCount = packCount
    }

    public var family: Family {
        switch unit {
        case .gram, .kilogram, .ounce, .pound: return .mass
        case .milliliter, .liter, .fluidOunce: return .volume
        case .count: return .count
        }
    }

    /// Grams, milliliters or items, for one unit of the pack.
    public var baseValue: Double {
        switch unit {
        case .gram, .milliliter, .count: return value
        case .kilogram, .liter: return value * 1000
        case .ounce: return value * 28.3495
        case .pound: return value * 453.592
        case .fluidOunce: return value * 29.5735
        }
    }

    /// Same amount within `tolerance` (relative), across units: 12 oz ≈ 340 g.
    public func isSameAmount(as o: MatchingQuantity, tolerance: Double = 0.03) -> Bool {
        guard family == o.family, (packCount ?? 1) == (o.packCount ?? 1) else { return false }
        let a = baseValue, b = o.baseValue
        guard a > 0, b > 0 else { return a == b }
        return abs(a - b) / max(a, b) <= tolerance
    }

    /// "340 grams" / "1.5 liters" (plural) or "340 gram" (adjective: "a 340 gram one"). Packs: "6 pack".
    public func spoken(plural: Bool = true) -> String {
        if let n = packCount, n > 1 { return "\(n) pack" }
        let number = Self.format(value)
        let one = value == 1
        let word: String
        switch unit {
        case .gram: word = "gram"
        case .kilogram: word = "kilogram"
        case .milliliter: word = "milliliter"
        case .liter: word = "liter"
        case .ounce: word = "ounce"
        case .fluidOunce: word = "fluid ounce"
        case .pound: word = "pound"
        case .count: return "\(number) count"
        }
        return "\(number) \(word)" + (plural && !one ? "s" : "")
    }

    /// "a" or "an" before the spoken adjective form: "an 800 gram one", "an 11 ounce one", "a 680 gram one".
    public var article: String {
        if let n = packCount, n > 1 { return Self.startsWithVowelSound(String(n)) ? "an" : "a" }
        let whole = Self.format(value).split(separator: ".").first.map(String.init) ?? ""
        return Self.startsWithVowelSound(whole) ? "an" : "a"
    }

    /// First quantity in the text, or nil.
    public static func parse(_ text: String) -> MatchingQuantity? { all(in: text).first }

    /// Every quantity in the text, in order. Reads raw text (not normalized), so decimals survive: "1.36 kg".
    public static func all(in text: String) -> [MatchingQuantity] {
        let tokens = tokenize(text.lowercased())
        var out: [MatchingQuantity] = []
        var i = 0
        while i < tokens.count {
            guard case .number(let v) = tokens[i] else { i += 1; continue }
            // "6 x 355 ml"
            if i + 2 < tokens.count, case .word(let x) = tokens[i + 1], x == "x",
               case .number(let inner) = tokens[i + 2], let (u, used) = unit(tokens, i + 3) {
                if v >= 1, v == v.rounded() { out.append(MatchingQuantity(value: inner, unit: u, packCount: Int(v))) }
                i += 3 + used; continue
            }
            if let (u, used) = unit(tokens, i + 1) {
                out.append(MatchingQuantity(value: u == .count ? v.rounded() : v, unit: u))
                i += 1 + used; continue
            }
            i += 1
        }
        return out
    }

    // MARK: - Private

    private enum Token: Equatable { case number(Double), word(String) }

    private static let units: [String: Unit] = [
        "g": .gram, "gr": .gram, "gm": .gram, "grams": .gram, "gram": .gram, "grammes": .gram,
        "kg": .kilogram, "kgs": .kilogram, "kilo": .kilogram, "kilos": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram,
        "ml": .milliliter, "milliliter": .milliliter, "milliliters": .milliliter, "millilitre": .milliliter, "millilitres": .milliliter,
        "l": .liter, "lt": .liter, "ltr": .liter, "liter": .liter, "liters": .liter, "litre": .liter, "litres": .liter,
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "floz": .fluidOunce,
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound,
        "ct": .count, "count": .count, "pk": .count, "pack": .count, "pcs": .count, "pieces": .count, "bags": .count, "pods": .count,
    ]

    /// Unit starting at token `i`; returns the unit and how many tokens it used.
    private static func unit(_ t: [Token], _ i: Int) -> (Unit, Int)? {
        guard i < t.count, case .word(let w) = t[i] else { return nil }
        if w == "fl" || w == "fluid", i + 1 < t.count, case .word(let n) = t[i + 1], ["oz", "ounce", "ounces"].contains(n) {
            return (.fluidOunce, 2)
        }
        if w == "cl" { return nil }   // rare; not worth a unit
        return units[w].map { ($0, 1) }
    }

    /// Numbers (with "." or "," decimals; "1,000" as thousands) and letter words; everything else separates.
    private static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        let chars = Array(s)
        var i = 0
        func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
        func isLetter(_ c: Character) -> Bool { c.isASCII && c.isLetter }
        while i < chars.count {
            let c = chars[i]
            if isDigit(c) {
                var j = i
                var text = ""
                while j < chars.count, isDigit(chars[j]) { text.append(chars[j]); j += 1 }
                if j + 1 < chars.count, chars[j] == "." || chars[j] == ",", isDigit(chars[j + 1]) {
                    var k = j + 1, frac = ""
                    while k < chars.count, isDigit(chars[k]) { frac.append(chars[k]); k += 1 }
                    if chars[j] == ",", frac.count == 3 { text += frac } else { text += "." + frac }
                    j = k
                }
                out.append(.number(Double(text) ?? 0))
                i = j
            } else if isLetter(c) {
                var j = i, w = ""
                while j < chars.count, isLetter(chars[j]) { w.append(chars[j]); j += 1 }
                if w == "fl", j < chars.count, chars[j] == "." { j += 1 }   // "fl. oz"
                out.append(.word(w))
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e9 { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func startsWithVowelSound(_ digits: String) -> Bool {
        if digits.hasPrefix("8") { return true }                                   // eight, eighty, eight hundred
        if digits == "11" || digits == "18" { return true }                        // eleven, eighteen
        if digits.count == 5 && (digits.hasPrefix("11") || digits.hasPrefix("18")) { return true }  // eleven thousand
        return false
    }
}

/// Spoken product name for confirmations: "Starbucks Dark Roast, 340 grams".
/// The brand is skipped when the name already starts with it; the size is added when it parses.
public func spokenProduct(_ p: ProductInfo, brand includeBrand: Bool = true, quantity includeQuantity: Bool = true) -> String {
    var name = p.name.trimmingCharacters(in: .whitespaces)
    if includeBrand, let b = p.brand?.trimmingCharacters(in: .whitespaces), !b.isEmpty,
       !normalizeText(name).hasPrefix(normalizeText(b)) {
        name = name.isEmpty ? b : "\(b) \(name)"
    }
    if includeQuantity, let q = p.quantity.flatMap(MatchingQuantity.parse) ?? MatchingQuantity.parse(p.name),
       !name.isEmpty {
        let spokenSize = q.spoken(plural: true)
        if !normalizeText(name).hasSuffix(normalizeText(spokenSize)) { name += ", \(spokenSize)" }
    }
    return name
}

/// "There's also a 680 gram one." when another candidate is the same product (brand + name, sizes ignored)
/// in a different size. nil when there's no other size or the current size is unknown.
public func variantAlternativeLine(current: ProductInfo, candidates: [ProductInfo]) -> String? {
    guard let mine = productQuantity(current) else { return nil }
    let key = productCoreName(current)
    guard !key.isEmpty else { return nil }
    for c in candidates where c != current && productCoreName(c) == key {
        guard let other = productQuantity(c), !other.isSameAmount(as: mine) else { continue }
        if let n = other.packCount, n > 1 { return "There's also \(other.article) \(n) pack." }
        return "There's also \(other.article) \(other.spoken(plural: false)) one."
    }
    return nil
}

func productQuantity(_ p: ProductInfo) -> MatchingQuantity? {
    p.quantity.flatMap(MatchingQuantity.parse) ?? MatchingQuantity.parse(p.name)
}

/// Normalized brand + name with size words removed ("Dark Roast 340g" → "dark roast").
func productCoreName(_ p: ProductInfo) -> String {
    let unitWords: Set<String> = ["g", "gr", "gm", "kg", "ml", "l", "lt", "oz", "fl", "lb", "lbs", "ct", "x",
                                  "gram", "grams", "kilogram", "kilograms", "liter", "liters", "litre", "litres",
                                  "ounce", "ounces", "pound", "pounds", "pack", "count"]
    let brand = normalizeText(p.brand ?? "")
    var words = normalizedWords(p.name).filter { w in
        !unitWords.contains(w) && !w.allSatisfy(\.isNumber) && !isNumberWithUnit(w)
    }
    if !brand.isEmpty && !words.joined(separator: " ").hasPrefix(brand) { words.insert(brand, at: 0) }
    return words.joined(separator: " ")
}

/// "340g", "1kg", "500ml" written without a space.
private func isNumberWithUnit(_ w: String) -> Bool {
    guard let first = w.first, first.isNumber else { return false }
    let letters = w.drop { $0.isNumber }
    return ["g", "kg", "ml", "l", "oz", "lb", "lbs", "ct"].contains(String(letters))
}
