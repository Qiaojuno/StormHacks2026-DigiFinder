/// Edit distance between two strings (characters).
public func levenshtein(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

/// True when `levenshtein(a, b) <= limit`, with a cheap length check first.
public func withinEditDistance(_ a: String, _ b: String, _ limit: Int) -> Bool {
    guard limit >= 0, abs(a.count - b.count) <= limit else { return false }
    return limit == 0 ? a == b : levenshtein(a, b) <= limit
}
