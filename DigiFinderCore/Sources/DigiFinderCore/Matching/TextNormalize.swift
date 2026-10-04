import Foundation

/// Must match the build script's normalize() exactly.
public func normalizeText(_ s: String) -> String {
    let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    // ASCII a–z / 0–9 only, like the script's [^a-z0-9 ] rule; everything else becomes a space.
    return String(folded.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : " " })
        .split(separator: " ").joined(separator: " ")
}

/// Digits only; 12-digit UPCs are padded to 13 like the database.
public func normalizeBarcode(_ raw: String) -> String {
    let d = raw.filter(\.isNumber); return d.count == 12 ? "0" + d : d
}
