import Foundation
import Observation
import DigiFinderCore

/// Main screen state (§6). UI state only; every intent goes to `SessionRunner` (§3.1).
@Observable @MainActor
final class AppViewModel {
    private(set) var stepTitle = "Ready"
    private(set) var lastMessage = ""
    private(set) var isWalking = false
    var showSetup = false
    var showDebug = false
    private(set) var status = UIStatus()

    let settings: UISettingsStore
    let debug: DebugViewModel
    let hint = "Volume ↑ talk · Volume ↓ done"
    #if targetEnvironment(simulator)
    let isSimulator = true
    #else
    let isSimulator = false
    #endif

    private let runner: SessionRunner
    /// Extra runner features (Wave 3); nil until `SessionRunner` adopts `UISessionDriving`.
    private let driver: UISessionDriving?
    private let readStatus: () -> UIStatus
    @ObservationIgnored private var didAppear = false

    init(env: AppEnvironment) {
        let runner = SessionRunner(env: env)
        let driver = (runner as AnyObject) as? UISessionDriving
        self.runner = runner
        self.driver = driver
        settings = UISettingsStore()

        let frames = env.frames
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
        debug = DebugViewModel(capture: env.frames as? CaptureControl, sources: sources, driver: driver,
                               onVolumeUp: { runner.volumeUp() }, onVolumeDown: { runner.volumeDown() })

        status = readStatus()
        settings.onChange = { [weak driver] s in driver?.apply(settings: s) }
        runner.onUpdate = { [weak self] step, message, walking in
            guard let self else { return }
            self.stepTitle = step.title
            self.lastMessage = message
            self.isWalking = walking
            self.refreshStatus()
        }
    }

    func onAppear() {
        refreshStatus()
        guard !didAppear else { return }
        didAppear = true
        driver?.apply(settings: settings.settings)
        if !settings.settings.hasHeardWalkthrough {
            showSetup = true
            playWalkthrough()
            settings.settings.hasHeardWalkthrough = true
        }
        runner.start()
    }

    /// The runner applies the walking / recording rules (§5.10).
    func talkTapped() { runner.screenTalkPressed() }
    func volumeUp()   { runner.volumeUp() }
    func volumeDown() { runner.volumeDown() }

    /// Re-reads the status chips (camera, LiDAR, database, online).
    func refreshStatus() {
        let s = readStatus()
        if s != status { status = s }
    }

    // MARK: Screen controls (ignored while walking, §5.10)

    func openSetup() {
        guard !isWalking else { return }
        showSetup = true
    }

    func openDebug() {
        guard !isWalking else { return }
        showDebug = true
    }

    func playWalkthrough() {
        driver?.speakWalkthrough(UIWalkthrough.lines)
    }

    /// Drag-to-hear on the accessible surface.
    func hear(_ text: String) {
        guard !isWalking else { return }
        driver?.speakScreenText(text)
    }

    /// Double-tap on the surface's "last message" row: the "Repeat" voice command.
    func repeatLast() {
        guard !isWalking else { return }
        driver?.inject(.routed(.command(.repeatLast)))
    }
}
