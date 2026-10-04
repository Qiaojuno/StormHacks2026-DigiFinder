import AVFoundation
import Foundation
import Speech

/// Microphone + speech recognition permissions.
enum VoicePermissions {
    static var isDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
            || [.denied, .restricted].contains(SFSpeechRecognizer.authorizationStatus())
    }

    /// Asks for whatever is still undetermined. True when both are granted.
    static func request() async -> Bool {
        guard await requestMicrophone() else { return false }
        return await requestSpeech()
    }

    static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
            }
        }
    }

    static func requestSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}
