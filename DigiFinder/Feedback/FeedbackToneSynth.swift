import Foundation
import DigiFinderCore

/// Generates the app's tones as in-memory 16-bit mono WAV data (no audio files).
enum FeedbackToneSynth {
    static let sampleRate = 44_100.0

    struct Note {
        var frequency: Double
        var start: Double
        var duration: Double
        var amplitude: Double
        /// Exponential decay rate (1/s); 0 = flat with short fades.
        var decay: Double
    }

    static func notes(for tone: Tone) -> [Note] {
        switch tone {
        case .beep:   // listening beep: short, clear, mid-high
            return [Note(frequency: 880, start: 0, duration: 0.12, amplitude: 0.55, decay: 0)]
        case .done:   // done chime: two rising notes with a soft tail
            return [Note(frequency: 660, start: 0, duration: 0.16, amplitude: 0.45, decay: 9),
                    Note(frequency: 990, start: 0.12, duration: 0.32, amplitude: 0.45, decay: 7)]
        case .tick:   // scan tick: very short click
            return [Note(frequency: 1_800, start: 0, duration: 0.025, amplitude: 0.4, decay: 120)]
        }
    }

    static func duration(of tone: Tone) -> Double {
        notes(for: tone).map { $0.start + $0.duration }.max() ?? 0
    }

    static func wav(for tone: Tone) -> Data {
        let notes = notes(for: tone)
        let count = Int((duration(of: tone) * sampleRate).rounded(.up))
        var samples = [Double](repeating: 0, count: count)
        let fade = 0.004
        for n in notes {
            let first = Int(n.start * sampleRate)
            let length = Int(n.duration * sampleRate)
            for i in 0..<length where first + i < count {
                let t = Double(i) / sampleRate
                var env = n.decay > 0 ? exp(-n.decay * t) : 1
                env *= min(1, t / fade, (n.duration - t) / fade)
                let wave = sin(2 * .pi * n.frequency * t) + 0.25 * sin(4 * .pi * n.frequency * t)
                samples[first + i] += n.amplitude * env * wave / 1.25
            }
        }
        return encode(samples)
    }

    private static func encode(_ samples: [Double]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for s in samples { append(Int16(max(-1, min(1, s)) * Double(Int16.max))) }
        return data
    }
}
