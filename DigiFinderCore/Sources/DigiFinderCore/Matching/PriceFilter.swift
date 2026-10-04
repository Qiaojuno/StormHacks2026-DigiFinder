/// Text that's mostly prices at the shelf edge isn't a product (§5.2).
/// Price when it has a currency sign, a unit-price marker ("/kg", "/lb", "/100 g", "per kg", "unit price"),
/// a bare decimal price ("3.99", "12,99" not followed by a size unit), or more than half its
/// non-space characters are digits.
public func isPriceTag(_ text: String) -> Bool {
    let t = text.lowercased()
    let compact = t.filter { !$0.isWhitespace }
    guard !compact.isEmpty else { return false }
    if t.contains("$") || t.contains("¢") || t.contains("€") || t.contains("£") { return true }
    let slashMarkers = ["/kg", "/lb", "/100g", "/100 g", "/100ml", "/100 ml", "/ 100", "/ea", "/l "]
    if slashMarkers.contains(where: { (t + " ").contains($0) }) { return true }
    let n = normalizeText(t)
    let wordMarkers = ["per kg", "per lb", "per 100", "unit price", "prix unitaire", "each", "ea"]
    if wordMarkers.contains(where: { containsPhrase(n, $0) }) { return true }
    if hasBareDecimalPrice(t) { return true }
    let digits = compact.filter { $0.isASCII && $0.isNumber }.count
    return Double(digits) / Double(compact.count) > 0.5
}

/// "3.99" or "12,99" (exactly two decimals) that isn't a size ("2.25 oz", "1.36 kg").
private func hasBareDecimalPrice(_ t: String) -> Bool {
    let c = Array(t)
    var i = 0
    func digit(_ k: Int) -> Bool { k >= 0 && k < c.count && c[k].isASCII && c[k].isNumber }
    while i < c.count {
        if (c[i] == "." || c[i] == ","), digit(i - 1), digit(i + 1), digit(i + 2), !digit(i + 3) {
            var j = i + 3
            while j < c.count, c[j] == " " { j += 1 }
            var unit = ""
            while j < c.count, c[j].isASCII, c[j].isLetter { unit.append(c[j]); j += 1 }
            let sizeUnits: Set<String> = ["g", "kg", "ml", "l", "oz", "lb", "lbs", "fl", "ct", "gr", "lt", "x"]
            if !sizeUnits.contains(unit) { return true }
        }
        i += 1
    }
    return false
}
