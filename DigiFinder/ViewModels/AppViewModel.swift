import AVFoundation
import Foundation
import Observation
import DigiFinderCore

/// The two pages: Home (live 0.5× view + record button) and Settings (setup, licenses, debug).
enum UIPage: Equatable { case home, settings }

/// Main screen state (§6). UI state only; every intent goes to `SessionRunner` (§3.1).
@Observable @MainActor
final class AppViewModel {
    private(set) var stepTitle = "Ready"
    private(set) var lastMessage = ""
    private(set) var isWalking = false
    private(set) var page: UIPage = .home
    /// A recording is running (the mic is on).
    private(set) var isRecording = false
    /// The stream is running (camera, danger, prompts): the record button shows stop.
    private(set) var isStreaming = false
    private(set) var status = UIStatus()
    /// Screen caption (top centre): what the user said and the app's last spoken line. Fades ~5 s after the last
    /// change. For judges, low-vision users and helpers; hidden from VoiceOver (everything is already spoken).
    private(set) var captionYou = ""
    private(set) var captionApp = ""
    private(set) var captionVisible = false
    @ObservationIgnored private var captionToken = 0
    static let captionSeconds = 5.0

    let settings: UISettingsStore
    let debug: DebugViewModel
    #if targetEnvironment(simulator)
    let isSimulator = true
    #else
    let isSimulator = false
    #endif

    private let runner: SessionRunner
    private let frames: FrameSource
    private let readStatus: () -> UIStatus
    @ObservationIgnored private var didAppear = false

    init(env: AppEnvironment) {
        let runner = SessionRunner(env: env)
        self.runner = runner
        settings = UISettingsStore()
        // Which way up the phone hangs is detected from gravity by the runner (owner decision); start upright.
        CaptureOrientation.set(upsideDown: false)

        let frames = env.frames
        self.frames = frames
        let hasDatabase = env.products != nil
        let system = env.system
        readStatus = {
            let caps = frames.capabilities
            return UIStatus(cameraAvailable: caps.cameraAvailable, hasLiDAR: caps.hasLiDAR,
                            hasOfflineDatabase: hasDatabase, isOnline: system.isOnline)
        }

        var seen = Set<ObjectIdentifier>()
        let candidates: [AnyObject] = [runner, env.safety, env.perception, env.feedback, env.detector]
        let sources = candidates.compactMap { $0 as? UIDebugSnapshotSource }
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
        debug = DebugViewModel(capture: env.frames, sources: sources, driver: runner,
                               onVolumeUp: { runner.volumeUp() }, onVolumeDown: { runner.volumeDown() })

        status = readStatus()
        settings.onChange = { [weak runner] s in runner?.apply(settings: s) }
        runner.onListeningChange = { [weak self] listening in
            self?.isRecording = listening
            if listening { self?.caption(you: "") }                      // a new recording: fresh words
        }
        env.voice.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.caption(you: text) }
        }
        env.feedback.onLineSpoken = { [weak self] text in
            Task { @MainActor in self?.caption(app: text) }
        }
        runner.onStreamingChange = { [weak self] streaming in self?.isStreaming = streaming }
        runner.onUpdate = { [weak self] step, message, walking in
            guard let self else { return }
            self.stepTitle = step.title
            self.lastMessage = message
            self.isWalking = walking
            self.refreshStatus()
        }
    }

    private func caption(you: String? = nil, app: String? = nil) {
        if let you { captionYou = you }
        if let app { captionApp = app }
        captionVisible = !captionYou.isEmpty || !captionApp.isEmpty
        captionToken += 1
        let token = captionToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.captionSeconds))
            guard let self, self.captionToken == token, !self.isRecording else { return }
            self.captionVisible = false
            self.captionYou = ""
            self.captionApp = ""
        }
    }

    func onAppear() {
        refreshStatus()
        guard !didAppear else { return }
        didAppear = true
        runner.apply(settings: settings.settings)
        if !settings.settings.hasHeardWalkthrough {
            page = .settings
            playWalkthrough()
            settings.settings.hasHeardWalkthrough = true
        }
        runner.start()
    }

    /// Record button (owner decision): while the stream runs it is stop (= volume down: everything stops); when stopped
    /// it starts the stream and a recording like volume up (ignored while walking, §5.10).
    func recordTapped() { runner.screenTalkPressed() }
    func volumeUp()   { runner.volumeUp() }
    func volumeDown() { runner.volumeDown() }

    /// Re-reads camera / LiDAR / database / online status.
    func refreshStatus() {
        let s = readStatus()
        if s != status { status = s }
    }

    // MARK: Pages (screen controls are ignored while walking, §5.10; Home always works)

    func openHome() { page = .home }

    func openSettings() {
        guard !isWalking else { return }
        page = .settings
    }

    /// The Home background shows the live 0.5× feed.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) { frames.attachPreview(layer) }

    func playWalkthrough() {
        runner.speakWalkthrough(UIWalkthrough.lines)
    }
}
