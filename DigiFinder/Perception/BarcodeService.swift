import Foundation
import Vision
import DigiFinderCore

/// Passive barcode reading (§2: only if one passes the camera; never required). One instance per queue.
final class BarcodeService {
    let request: VNDetectBarcodesRequest

    init() {
        request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8, .upce]
    }

    /// Normalized codes (12-digit UPC-A padded to 13) from the last `perform` that included `request`.
    func results() -> [String] {
        var out: [String] = []
        for obs in request.results ?? [] {
            guard let payload = obs.payloadStringValue else { continue }
            let code = normalizeBarcode(payload)
            if code.count >= 8, !out.contains(code) { out.append(code) }
        }
        return out
    }
}
