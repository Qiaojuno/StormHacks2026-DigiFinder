import CoreGraphics
import Foundation
import Vision
import DigiFinderCore

/// Offline learning (§5.14): feature prints of confirmed products' label crops, matched later while scanning and
/// pointing. **A hint only, never a confirmation** (look-alike variants share a label design).
///
/// One small file per product in Application Support/ProductMemory, at most `maxPrintsPerProduct` prints each and
/// `maxProducts` products (the least recently confirmed go first). Loading (at init) and saving run on a background
/// queue; prints from another Vision revision are dropped at load. `hint(for:)` runs on the caller's queue: call it
/// from a capture/perception queue, never the main thread. Crops are expected upright.
final class ProductMemory: @unchecked Sendable {
    /// Largest print distance that still counts as the remembered product.
    /// Revision 2 prints (iOS 17+) are normalized: distances run about 0–2, the same label well under 1.
    /// verify on device (§10)
    static let hintMaxDistance: Float = 0.4
    /// Same, for revision 1 prints (unnormalized, much larger distances). verify on device (§10)
    static let hintMaxDistanceRevision1: Float = 15
    static let maxPrintsPerProduct = 5
    static let maxProducts = 2_000

    private struct Remembered { var entry: DataMemoryEntry; var prints: [VNFeaturePrintObservation] }

    private let directory: URL?
    private let revision = VNGenerateImageFeaturePrintRequest.defaultRevision
    private let queue = DispatchQueue(label: "DigiFinder.ProductMemory", qos: .utility)
    private let lock = NSLock()
    private var store: [String: Remembered] = [:]

    /// Application Support/ProductMemory.
    convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.init(directory: base?.appendingPathComponent("ProductMemory", isDirectory: true))
    }

    /// `directory` nil keeps everything in memory (tests, previews).
    init(directory: URL?) {
        self.directory = directory
        queue.async { [self] in load() }
    }

    // MARK: Frozen API (§3.3)

    /// Remembers a confirmed product's label crop. Returns at once; the print is made and written in the background.
    func save(_ p: ProductInfo, crop: CGImage) {
        let key = Self.key(for: p)
        guard !key.isEmpty else { return }
        queue.async { [self] in
            guard let fp = featurePrint(crop),
                  let data = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true) else { return }
            lock.lock()
            var item = store[key] ?? Remembered(entry: DataMemoryEntry(product: p, prints: [], revision: revision, updated: Date()),
                                                prints: [])
            item.entry.product = p
            item.entry.revision = revision
            item.entry.updated = Date()
            item.entry.prints.append(data)
            item.prints.append(fp)
            let extra = item.prints.count - Self.maxPrintsPerProduct
            if extra > 0 { item.entry.prints.removeFirst(extra); item.prints.removeFirst(extra) }
            store[key] = item
            let evicted = evictLocked()
            lock.unlock()
            write(item.entry, key: key)
            evicted.forEach(remove)
        }
    }

    /// The remembered product whose label looks most like `crop`, if close enough. Never final: confirm by label.
    func hint(for crop: CGImage) -> ProductInfo? {
        lock.lock()
        let items = Array(store.values)
        lock.unlock()
        guard !items.isEmpty, let fp = featurePrint(crop) else { return nil }
        let limit = fp.requestRevision >= 2 ? Self.hintMaxDistance : Self.hintMaxDistanceRevision1
        var best: (product: ProductInfo, distance: Float)?
        for item in items {
            for stored in item.prints {
                var d: Float = 0
                guard (try? fp.computeDistance(&d, to: stored)) != nil else { continue }
                if d < best?.distance ?? .infinity { best = (item.entry.product, d) }
            }
        }
        guard let best, best.distance <= limit else { return nil }
        return best.product
    }

    // MARK: Additive API

    /// Products currently remembered (0 until the launch load finishes).
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return store.count
    }

    /// Waits for the launch load and any pending saves (tests).
    func flush() { queue.sync {} }

    // MARK: Vision

    private func featurePrint(_ crop: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        do {
            try VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:]).perform([request])
        } catch {
            return nil
        }
        return request.results?.first
    }

    // MARK: Storage

    private func load() {
        guard let directory else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [String: Remembered] = [:]
        for url in files where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? PropertyListDecoder().decode(DataMemoryEntry.self, from: data),
                  entry.revision == revision else {          // unreadable, or prints from an old Vision revision
                try? fm.removeItem(at: url)
                continue
            }
            let prints = entry.prints.compactMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: $0)
            }
            let key = Self.key(for: entry.product)
            guard !prints.isEmpty, !key.isEmpty else { try? fm.removeItem(at: url); continue }
            loaded[key] = Remembered(entry: entry, prints: prints)
        }
        lock.lock()
        store = loaded
        let evicted = evictLocked()
        lock.unlock()
        evicted.forEach(remove)
    }

    /// Drops the least recently confirmed products above the cap; returns their keys (files deleted by the caller).
    private func evictLocked() -> [String] {
        let extra = store.count - Self.maxProducts
        guard extra > 0 else { return [] }
        let oldest = store.sorted { $0.value.entry.updated < $1.value.entry.updated }.prefix(extra).map(\.key)
        oldest.forEach { store[$0] = nil }
        return oldest
    }

    private func write(_ entry: DataMemoryEntry, key: String) {
        guard let directory else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(Self.fileName(for: key)), options: .atomic)
    }

    private func remove(_ key: String) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.fileName(for: key)))
    }

    /// Barcode when known; otherwise the normalized brand + name + quantity (hand-added products have no code).
    private static func key(for p: ProductInfo) -> String {
        let code = normalizeBarcode(p.code)
        if !code.isEmpty { return code }
        let text = normalizeText("\(p.brand ?? "") \(p.name) \(p.quantity ?? "")")
        return text.isEmpty ? "" : "name " + text
    }

    /// Stable across launches: the barcode itself, or an FNV-1a hash of the key.
    private static func fileName(for key: String) -> String {
        if key.allSatisfy(\.isNumber) { return key + ".plist" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return "n" + String(hash, radix: 16) + ".plist"
    }
}
