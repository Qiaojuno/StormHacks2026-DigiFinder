import Foundation

/// Must match the build script's normalize() exactly:
/// NFKD → drop combining marks → lowercase → every run of characters outside a–z / 0–9 becomes one space → trim.
/// Works on Unicode scalars like Python does, so "ﬁ" → "fi", "Café" → "cafe", and "ß" / "ø" are dropped (not folded).
public func normalizeText(_ s: String) -> String {
    var stripped = String.UnicodeScalarView()
    for u in s.decomposedStringWithCompatibilityMapping.unicodeScalars
    where u.properties.canonicalCombiningClass == .notReordered {
        stripped.append(u)
    }
    var out = String.UnicodeScalarView()
    var gap = false
    for u in String(stripped).lowercased().unicodeScalars {
        let v = u.value
        if (v >= 97 && v <= 122) || (v >= 48 && v <= 57) {
            if gap && !out.isEmpty { out.append(" ") }
            gap = false
            out.append(u)
        } else {
            gap = true
        }
    }
    return String(out)
}

/// ASCII digits only; 12-digit UPC-A codes are padded to 13 like the database.
public func normalizeBarcode(_ raw: String) -> String {
    let d = String(raw.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.map(Character.init))
    return d.count == 12 ? "0" + d : d
}

/// Words of `normalizeText(s)`.
public func normalizedWords(_ s: String) -> [String] {
    normalizeText(s).split(separator: " ").map(String.init)
}

/// Whole-word phrase containment. Both arguments must already be in normalizeText form.
/// With `allowPlural`, each word may differ by a trailing "s" / "es" (words of 3+ letters): "banana" ~ "bananas".
public func containsPhrase(_ text: String, _ phrase: String, allowPlural: Bool = false) -> Bool {
    let p = phrase.split(separator: " ")
    guard !p.isEmpty else { return false }
    if !allowPlural { return " \(text) ".contains(" \(phrase) ") }
    let w = text.split(separator: " ")
    guard w.count >= p.count else { return false }
    for i in 0...(w.count - p.count) where zip(w[i..<i + p.count], p).allSatisfy({ wordsMatchAllowingPlural($0, $1) }) {
        return true
    }
    return false
}

/// "bean" ~ "beans", "tomato" ~ "tomatoes". Exact for words shorter than 3 letters.
func wordsMatchAllowingPlural<A: StringProtocol, B: StringProtocol>(_ a: A, _ b: B) -> Bool {
    if a == b { return true }
    let (short, long) = a.count < b.count ? (String(a), String(b)) : (String(b), String(a))
    guard short.count >= 3 else { return false }
    return long == short + "s" || long == short + "es"
}
