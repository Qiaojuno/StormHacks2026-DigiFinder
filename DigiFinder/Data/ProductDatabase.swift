import Foundation
import SQLite3
import DigiFinderCore

private let dataSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The offline product database (`products.sqlite` from `tools/build_product_db.py`), opened read-only (§7.1, §9).
///
/// Schema: `products(code, name, brand, quantity, aisle, search)`, where `search` = normalize("brand name quantity")
/// and 12-digit UPCs are padded to 13; `products_fts` is FTS5 over `search` (external content, rowid = products.rowid).
/// Without FTS5 (or without the index) every search falls back to LIKE over `search`, with the same results.
/// Thread-safe: one connection, every statement runs under a lock.
final class ProductDatabase {
    /// A brand as stored in the database: the most common spelling and how many products carry it.
    struct Brand: Equatable { let name: String; let productCount: Int }

    /// false when FTS5 or the `products_fts` table is missing (LIKE fallback).
    let hasFullTextSearch: Bool

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var brands: [String: Brand]?            // normalized brand → brand (built once, lazily)

    private static let columns = "p.code, p.name, p.brand, p.quantity, p.aisle"

    /// nil if the file is missing or isn't a product database.
    init?(url: URL) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle,
              Self.runs(handle, "SELECT code, name, brand, quantity, aisle, search FROM products LIMIT 1") else {
            sqlite3_close(handle)
            return nil
        }
        db = handle
        hasFullTextSearch = Self.runs(handle, "SELECT rowid FROM products_fts WHERE products_fts MATCH 'a' LIMIT 1")
        DispatchQueue.global(qos: .utility).async { [weak self] in _ = self?.brandIndex() }   // warm the brand index
    }

    deinit { sqlite3_close(db) }

    // MARK: Frozen API (§3.3)

    /// Products whose search text contains every word of `text` (any order), best match first.
    func search(_ text: String, limit: Int) -> [ProductInfo] {
        search(text, aisle: nil, limit: limit)
    }

    /// Barcode lookup. Accepts UPC-A (padded like the database), EAN-13, EAN-8, GTIN-14 and UPC-E.
    func lookup(code: String) -> ProductInfo? {
        for candidate in Self.barcodeCandidates(code) {
            let sql = "SELECT \(Self.columns) FROM products p WHERE p.code = ? LIMIT 1"
            if let hit = rows(sql, [candidate], Self.product).first { return hit }
        }
        return nil
    }

    // MARK: Additive API

    /// Like `search(_:limit:)`, restricted to one aisle when `aisle` is set.
    func search(_ text: String, aisle: String?, limit: Int) -> [ProductInfo] {
        search(DataSearchQuery(words: text), aisle: aisle, limit: limit)
    }

    /// Runs a structured query, best match first: products matching the words as said come before those found
    /// only through another spelling or synonym (a rare alternative would otherwise outrank them). Products with
    /// the same brand, name and quantity (different barcodes) appear once.
    func search(_ query: DataSearchQuery, aisle: String? = nil, limit: Int) -> [ProductInfo] {
        guard !query.isEmpty, limit > 0 else { return [] }
        var found = rankedRows(query.primary, aisle: aisle, limit: limit)
        if found.count < limit, query != query.primary {
            var seen = Set(found.map(\.text))
            for row in rankedRows(query, aisle: aisle, limit: limit + found.count)
            where found.count < limit && seen.insert(row.text).inserted {
                found.append(row)
            }
        }
        return found.map(\.product)
    }

    /// Number of products matching `query` (in one aisle when `aisle` is set).
    func count(_ query: DataSearchQuery, aisle: String? = nil) -> Int {
        guard !query.isEmpty else { return 0 }
        var sql: String, args: [String]
        if hasFullTextSearch {
            sql = aisle == nil
                ? "SELECT count(*) FROM products_fts WHERE products_fts MATCH ?"
                : "SELECT count(*) FROM products_fts f JOIN products p ON p.rowid = f.rowid WHERE products_fts MATCH ?"
            args = [query.ftsExpression]
        } else {
            let like = query.likeClause(column: "p.search")
            sql = "SELECT count(*) FROM products p WHERE \(like.sql)"
            args = like.args
        }
        if let aisle { sql += " AND p.aisle = ?"; args.append(aisle) }
        return rows(sql, args) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    /// How many products match `query` in each aisle (products without an aisle are left out).
    func aisleCounts(_ query: DataSearchQuery) -> [String: Int] {
        guard !query.isEmpty else { return [:] }
        var sql: String, args: [String]
        if hasFullTextSearch {
            sql = "SELECT p.aisle, count(*) FROM products_fts f JOIN products p ON p.rowid = f.rowid WHERE products_fts MATCH ?"
            args = [query.ftsExpression]
        } else {
            let like = query.likeClause(column: "p.search")
            sql = "SELECT p.aisle, count(*) FROM products p WHERE \(like.sql)"
            args = like.args
        }
        sql += " AND p.aisle IS NOT NULL AND p.aisle <> '' GROUP BY p.aisle"
        var out: [String: Int] = [:]
        for (aisle, n) in rows(sql, args, { (Self.text($0, 0) ?? "", Int(sqlite3_column_int64($0, 1))) }) where !aisle.isEmpty {
            out[aisle] = n
        }
        return out
    }

    /// The database brand whose normalized name is exactly `normalized` ("great value" → "Great Value").
    func brand(_ normalized: String) -> Brand? {
        brandIndex()[normalized]
    }

    /// Products whose brand is `normalized` or starts with it as whole words ("kirkland" counts "Kirkland Signature").
    func brandFamilyCount(_ normalized: String) -> Int {
        guard !normalized.isEmpty else { return 0 }
        let prefix = normalized + " "
        return brandIndex().reduce(0) { $0 + ($1.key == normalized || $1.key.hasPrefix(prefix) ? $1.value.productCount : 0) }
    }

    // MARK: Barcodes

    /// The normalized code first, then other spellings of the same product.
    static func barcodeCandidates(_ raw: String) -> [String] {
        let code = normalizeBarcode(raw)
        guard !code.isEmpty else { return [] }
        var out = [code]
        if code.count == 14, code.hasPrefix("0") { out.append(String(code.dropFirst())) }   // GTIN-14 → EAN-13
        if code.count == 8, let upcA = expandUPCE(code) { out.append(upcA) }                 // UPC-E → UPC-A (13 digits)
        return out
    }

    /// UPC-E (number system 0/1, six digits, check digit) → UPC-A padded to 13 digits like the database.
    static func expandUPCE(_ code: String) -> String? {
        let d = code.compactMap(\.wholeNumberValue)
        guard d.count == 8, d[0] <= 1 else { return nil }
        let m = d[1...6].map(String.init), last = d[6]
        let body: String
        switch last {
        case 0...2: body = m[0] + m[1] + m[5] + "0000" + m[2] + m[3] + m[4]
        case 3:     body = m[0] + m[1] + m[2] + "00000" + m[3] + m[4]
        case 4:     body = m[0] + m[1] + m[2] + m[3] + "00000" + m[4]
        default:    body = m[0] + m[1] + m[2] + m[3] + m[4] + "0000" + m[5]
        }
        return "0" + String(d[0]) + body + String(d[7])
    }

    // MARK: SQLite

    private func brandIndex() -> [String: Brand] {
        lock.lock(); defer { lock.unlock() }
        if let brands { return brands }
        var totals: [String: Int] = [:], best: [String: (name: String, count: Int)] = [:]
        let sql = "SELECT brand, count(*) FROM products WHERE brand IS NOT NULL AND brand <> '' GROUP BY brand"
        for (raw, n) in rows(sql, [], { (Self.text($0, 0) ?? "", Int(sqlite3_column_int64($0, 1))) }) {
            let key = normalizeText(raw)
            guard !key.isEmpty else { continue }
            totals[key, default: 0] += n
            if n > best[key]?.count ?? 0 { best[key] = (raw.trimmingCharacters(in: .whitespaces), n) }
        }
        var index: [String: Brand] = [:]
        for (key, total) in totals { index[key] = Brand(name: best[key]?.name ?? key, productCount: total) }
        brands = index
        return index
    }

    /// One row per distinct search text, best first (FTS5 rank, or shortest text with LIKE).
    private func rankedRows(_ query: DataSearchQuery, aisle: String?, limit: Int) -> [(product: ProductInfo, text: String)] {
        var sql: String, args: [String]
        let columns = "\(Self.columns), p.search"
        if hasFullTextSearch {
            sql = "SELECT \(columns) FROM products_fts f JOIN products p ON p.rowid = f.rowid WHERE products_fts MATCH ?"
            args = [query.ftsExpression]
        } else {
            let like = query.likeClause(column: "p.search")
            sql = "SELECT \(columns) FROM products p WHERE \(like.sql)"
            args = like.args
        }
        if let aisle { sql += " AND p.aisle = ?"; args.append(aisle) }
        sql += " GROUP BY p.search ORDER BY " + (hasFullTextSearch ? "min(f.rank)" : "length(p.search)") + " LIMIT \(limit)"
        return rows(sql, args) { (Self.product($0), Self.text($0, 5) ?? "") }
    }

    private func rows<T>(_ sql: String, _ args: [String], _ read: (OpaquePointer) -> T) -> [T] {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, dataSQLiteTransient) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(read(stmt)) }
        return out
    }

    private static func product(_ stmt: OpaquePointer) -> ProductInfo {
        ProductInfo(code: text(stmt, 0) ?? "", name: text(stmt, 1) ?? "",
                    brand: nonEmpty(text(stmt, 2)), quantity: nonEmpty(text(stmt, 3)), aisle: nonEmpty(text(stmt, 4)))
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }

    /// true if `sql` prepares and steps without an error (used to probe the schema and FTS5).
    private static func runs(_ db: OpaquePointer, _ sql: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        let rc = sqlite3_step(stmt)
        return rc == SQLITE_ROW || rc == SQLITE_DONE
    }
}
