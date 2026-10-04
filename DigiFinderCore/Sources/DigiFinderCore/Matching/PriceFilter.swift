/// Text that's mostly prices at the shelf edge isn't a product (§5.2).
public func isPriceTag(_ text: String) -> Bool {
    let t = text.lowercased()
    let digits = t.filter(\.isNumber).count
    return t.contains("$") || t.contains("/kg") || t.contains("/lb") || t.contains("¢") || Double(digits) / Double(max(t.count, 1)) > 0.5
}
