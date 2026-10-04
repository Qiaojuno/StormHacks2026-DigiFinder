# Contract change requests

Wave 2 agents append here instead of editing `DigiFinderCore/Sources/DigiFinderCore/Contracts/` or `DigiFinder/Protocols/`.
Work around the gap with a local adapter in your own folder until Wave 3 applies the change.
Wave 3 applies every entry consistently, then clears this file.

Template:

## <short title>
- **Who:** <agent>
- **What:** <exact change: type, member, signature>
- **Why:** <what breaks or is impossible without it>
- **Affects:** <other modules or agents>
- **Local workaround:** <adapter you used meanwhile>

---

## FrameSource: capability changes, thermal/rate hooks, debug snapshots
- **Who:** Capture
- **What:** Add to `FrameSource` (or make `AppEnvironment.frames` a `FrameSource & CaptureControl`) the members of
  `Capture/CaptureControl.swift`: `var onCapabilitiesChange: ((CaptureCapabilities) -> Void)?`,
  `func setThermalLevel(_: ThermalLevel)`, `func setRates(_: CaptureRates)`, `var rates: CaptureRates { get }`,
  `func makeStreamB() -> AsyncStream<FrameB>`, and the read-only debug members (`debugInfo`, `latestDepthSummary`,
  `latestDebugImage`, `latestDepthHeatmap`, `debugOverlayEnabled`).
- **Why:** `start()` returns at once and configures/asks permission on a background queue, so a denial or a failed
  configuration shows up later; the runner needs a callback to send `SystemEvent.cameraDenied` when
  `capabilities.cameraAvailable` turns false. `start()` also throws `CaptureError.denied` if permission is already denied.
  §5.16 thermal throttling needs a way to lower capture rates (the camera's own system pressure is applied automatically).
- **Affects:** Wave 3 runner (`.thermal(level)` → `setThermalLevel`; capability callback → `.system(.cameraDenied)`), UI debug overlay.
- **Local workaround:** `protocol CaptureControl` adopted by `MultiCamService`, `FallbackCameraService`, `NoCameraSource`;
  use `(env.frames as? CaptureControl)`.

## FrameSource.streamB is single-consumer
- **Who:** Capture
- **What:** Document `streamB` as one consumer only, or replace it with `func makeStreamB() -> AsyncStream<FrameB>`
  (each call a new `bufferingNewest(1)` subscription).
- **Why:** An `AsyncStream` traps or splits elements when two tasks iterate it. If both Safety (YOLO labels) and
  Perception iterate `frames.streamB`, the app breaks.
- **Affects:** Safety, Perception, Wave 3.
- **Local workaround:** `CaptureControl.makeStreamB()` already fans the same frames out to extra subscribers.

## DepthProvider.distance(at:) point space
- **Who:** Capture
- **What:** Doc comment only: `p` is a point of Stream B's upright portrait image (the only camera image perception
  sees); the result is meters along the viewing ray (median of a 5×5 depth window), nil outside the LiDAR field of view.
- **Why:** The LiDAR depth covers the 1× field of view, about half of the 0.5× image; mapping needs Stream B intrinsics.
- **Affects:** Perception (door/shelf distances), Safety.
- **Local workaround:** `LiDARDepthProvider(calibration:)` reads the latest Stream B intrinsics from a shared
  `CaptureCalibration` that the frame source updates; `CaptureFactory.makeBest()` wires both. Without it a nominal 2× zoom is used.

## Capture initializers and live wiring
- **Who:** Capture
- **What:** `AppEnvironment.live()` should use `let (frames, depth) = CaptureFactory.makeBest()` (LiDAR+ultra-wide →
  ultra-wide → wide → `NoCameraSource`). Init changes: `MultiCamService(lidar:ultraWide:calibration:)` or failable
  `MultiCamService(calibration:)`; `FallbackCameraService(device:calibration:)` or failable `FallbackCameraService(calibration:)`.
  Unchanged: `NoCameraSource()`, `LiDARDepthProvider()`, `EstimatedDepthProvider()`.
- **Why:** The stub inits had no devices; the factory keeps device choice in Capture.
- **Affects:** Wave 3 (`App/AppEnvironment.swift`).
- **Local workaround:** none needed; current `AppEnvironment` still compiles.

## Request.products needs a GoalChange
- **Who:** Core-logic
- **What:** `Request.products([Goal])` → `case products([Goal], GoalChange)` in `Contracts/Requests.swift`.
  The router fills it like `.product` ("actually coffee and milk" → `.replace`, "also coffee and milk" → `.add`, bare → `.unspecified`).
- **Why:** with no change slot, "actually coffee and milk" can't say "replace the current goal with both", and "also coffee and milk"
  can't be told apart from a fresh list, so the session has to guess.
- **Affects:** Core-session (`ShoppingSession` handling of `.routed(.products)`), Wave 3 runner. `RouterTests`' `case .products?:` pattern
  still compiles unchanged.
- **Local workaround:** `RequestRouter.routeWithChange(_:) -> RoutingResult` returns the request plus the implied `GoalChange`
  (`RequestRouter.goalChange(_:)` is also public). The runner can call it instead of `route(_:)` until the contract changes.

## Flow runtime semantics (doc comments on `SessionEvent` / `Effect`)
- **Who:** Core-session
- **What:** No signature change. Add doc comments to `Contracts/Session.swift` so the runner and Perception match what `ShoppingSession` expects:
  - `.tick(t)`: a monotonic clock in seconds (e.g. `CACurrentMediaTime()`), sent every ~0.5 s. The first tick only sets the reference. A gap longer than 5 s counts as 5 s.
  - `.listen(maxSeconds:)`: wait until `feedback.isSpeaking` is false (max ~3 s), then beep, then record. The session never emits a separate `.chime(.beep)`.
  - An empty or silent recording must arrive as `.notUnderstood(noisy:)`, because the auto-listen fallbacks depend on it ("I'll add milk to the list.", "Shopping done…"). A cancelled recording sends nothing.
  - `.motion(yawDegrees:)`: heading in degrees that grows clockwise (turning right), the same sense as `clockPosition(degreesRight:)`. `steps` is the cumulative pedometer count.
  - Stairs lines come from the session as `.say(_, .stairs)`. Danger lines come only from `SafetyService` → `FeedbackOutput.danger`. `.danger(cutRecording: true)` → the session says "Say that again." and listens.
  - `.talkPressed` doesn't say which button was pressed. The runner applies the screen Talk rules before forwarding the press: ignore it while walking, and if it comes while recording, say "Press the volume down button to finish," without forwarding.
  - Perception: `PointedProduct.match >= 0.8` means it's the goal ("Grab it."). `AisleSign.number == nil` marks a shelf or section label (the only signs used inside the aisle). `.aisleVerdict(nil, …)` means unsure. `.confirmed(nil, _)` means unclear (the session's timers prompt).
  - `.productLookedUp(Goal?)`: a goal with `category` = an aisle was found. A goal without `category` (with `signWords`) = word search. `nil` = nothing found, and is also what the runner sends on error.
  - Wiring: build the session with `ShoppingSession(catalog: catalog.aisles, destinations: catalog.destinations)`. This init is Flow-owned. `init(catalog:)` is kept and falls back to the §5.6 keywords.
- **Why:** The frozen contract doesn't say any of this. If a side assumes differently, timers, listening or the entrance bearing break without any error.
- **Affects:** Wave 3 SessionRunner, Perception, Voice.
- **Local workaround:** Implemented as listed. The same notes are in the header of `Flow/ShoppingSession.swift`.

## EntrancePick needs a clock position computed from intrinsics
- **Who:** Core-session
- **What:** Add `public var clock: Int?` and `public var cartCorralClock: Int?` to `EntrancePick` (optional, so the Codable decoding of the Gemini response is unchanged). The runner fills them with `clockPosition(degreesRight: Geometry.degreesRight(portraitX:intrinsics:sensorHeight:))` before it sends `.entrancePicked`.
- **Why:** The session only gets `x` (0…1 across the upright still) and has no Stream B intrinsics, so "Entrance at 1 o'clock." is only an estimate.
- **Affects:** Wave 3 runner (or Network), Core-session.
- **Local workaround:** `Geometry.degreesRight(portraitX:horizontalFOV:)` with a nominal 92° portrait FOV (`SessionTuning.stillHorizontalFOV`).

## Shelf distance event for "The shelf is about one step ahead."
- **Who:** Core-session
- **What:** Add `case shelfDistance(Float)` to `SessionEvent`: LiDAR meters to the shelf, sent while `StreamWork.shelfMode` is on, at most once per ~2 s.
- **Why:** §5.2 "Point at the shelf" calls for this line, but no event carries the distance.
- **Affects:** Safety or Perception (sender), Wave 3 runner, Core-session.
- **Local workaround:** None. The line isn't spoken yet; "Step back a little" still comes from `.positioning(.stepBack)`.

## FrameSource: capability changes, thermal/rate hooks, debug snapshots
- **Who:** Capture
- **What:** Add to `FrameSource` (or make `AppEnvironment.frames` a `FrameSource & CaptureControl`) the members of
  `Capture/CaptureControl.swift`: `var onCapabilitiesChange: ((CaptureCapabilities) -> Void)?`,
  `func setThermalLevel(_: ThermalLevel)`, `func setRates(_: CaptureRates)`, `var rates: CaptureRates { get }`,
  `func makeStreamB() -> AsyncStream<FrameB>`, and the read-only debug members (`debugInfo`, `latestDepthSummary`,
  `latestDebugImage`, `latestDepthHeatmap`, `debugOverlayEnabled`).
- **Why:** `start()` returns at once and configures/asks permission on a background queue, so a denial or a failed
  configuration shows up later; the runner needs a callback to send `SystemEvent.cameraDenied` when
  `capabilities.cameraAvailable` turns false. `start()` also throws `CaptureError.denied` if permission is already denied.
  §5.16 thermal throttling needs a way to lower capture rates (the camera's own system pressure is applied automatically).
- **Affects:** Wave 3 runner (`.thermal(level)` → `setThermalLevel`; capability callback → `.system(.cameraDenied)`), UI debug overlay.
- **Local workaround:** `protocol CaptureControl` adopted by `MultiCamService`, `FallbackCameraService`, `NoCameraSource`;
  use `(env.frames as? CaptureControl)`.

## FrameSource.streamB is single-consumer
- **Who:** Capture
- **What:** Document `streamB` as one consumer only, or replace it with `func makeStreamB() -> AsyncStream<FrameB>`
  (each call a new `bufferingNewest(1)` subscription).
- **Why:** An `AsyncStream` traps or splits elements when two tasks iterate it. If both Safety (YOLO labels) and
  Perception iterate `frames.streamB`, the app breaks.
- **Affects:** Safety, Perception, Wave 3.
- **Local workaround:** `CaptureControl.makeStreamB()` already fans the same frames out to extra subscribers.

## DepthProvider.distance(at:) point space
- **Who:** Capture
- **What:** Doc comment only: `p` is a point of Stream B's upright portrait image (the only camera image perception
  sees); the result is meters along the viewing ray (median of a 5×5 depth window), nil outside the LiDAR field of view.
- **Why:** The LiDAR depth covers the 1× field of view, about half of the 0.5× image; mapping needs Stream B intrinsics.
- **Affects:** Perception (door/shelf distances), Safety.
- **Local workaround:** `LiDARDepthProvider(calibration:)` reads the latest Stream B intrinsics from a shared
  `CaptureCalibration` that the frame source updates; `CaptureFactory.makeBest()` wires both. Without it a nominal 2× zoom is used.

## Capture initializers and live wiring
- **Who:** Capture
- **What:** `AppEnvironment.live()` should use `let (frames, depth) = CaptureFactory.makeBest()` (LiDAR+ultra-wide →
  ultra-wide → wide → `NoCameraSource`). Init changes: `MultiCamService(lidar:ultraWide:calibration:)` or failable
  `MultiCamService(calibration:)`; `FallbackCameraService(device:calibration:)` or failable `FallbackCameraService(calibration:)`.
  Unchanged: `NoCameraSource()`, `LiDARDepthProvider()`, `EstimatedDepthProvider()`.
- **Why:** The stub inits had no devices; the factory keeps device choice in Capture.
- **Affects:** Wave 3 (`App/AppEnvironment.swift`).
- **Local workaround:** none needed; current `AppEnvironment` still compiles.

## Request.products needs a GoalChange
- **Who:** Core-logic
- **What:** `Request.products([Goal])` → `case products([Goal], GoalChange)` in `Contracts/Requests.swift`.
  The router fills it like `.product` ("actually coffee and milk" → `.replace`, "also coffee and milk" → `.add`, bare → `.unspecified`).
- **Why:** with no change slot, "actually coffee and milk" can't say "replace the current goal with both", and "also coffee and milk"
  can't be told apart from a fresh list, so the session has to guess.
- **Affects:** Core-session (`ShoppingSession` handling of `.routed(.products)`), Wave 3 runner. `RouterTests`' `case .products?:` pattern
  still compiles unchanged.
- **Local workaround:** `RequestRouter.routeWithChange(_:) -> RoutingResult` returns the request plus the implied `GoalChange`
  (`RequestRouter.goalChange(_:)` is also public). The runner can call it instead of `route(_:)` until the contract changes.

## Flow runtime semantics (doc comments on `SessionEvent` / `Effect`)
- **Who:** Core-session
- **What:** No signature change. Add doc comments to `Contracts/Session.swift` so the runner and Perception match what `ShoppingSession` expects:
  - `.tick(t)`: a monotonic clock in seconds (e.g. `CACurrentMediaTime()`), sent every ~0.5 s. The first tick only sets the reference. A gap longer than 5 s counts as 5 s.
  - `.listen(maxSeconds:)`: wait until `feedback.isSpeaking` is false (max ~3 s), then beep, then record. The session never emits a separate `.chime(.beep)`.
  - An empty or silent recording must arrive as `.notUnderstood(noisy:)`, because the auto-listen fallbacks depend on it ("I'll add milk to the list.", "Shopping done…"). A cancelled recording sends nothing.
  - `.motion(yawDegrees:)`: heading in degrees that grows clockwise (turning right), the same sense as `clockPosition(degreesRight:)`. `steps` is the cumulative pedometer count.
  - Stairs lines come from the session as `.say(_, .stairs)`. Danger lines come only from `SafetyService` → `FeedbackOutput.danger`. `.danger(cutRecording: true)` → the session says "Say that again." and listens.
  - `.talkPressed` doesn't say which button was pressed. The runner applies the screen Talk rules before forwarding the press: ignore it while walking, and if it comes while recording, say "Press the volume down button to finish," without forwarding.
  - Perception: `PointedProduct.match >= 0.8` means it's the goal ("Grab it."). `AisleSign.number == nil` marks a shelf or section label (the only signs used inside the aisle). `.aisleVerdict(nil, …)` means unsure. `.confirmed(nil, _)` means unclear (the session's timers prompt).
  - `.productLookedUp(Goal?)`: a goal with `category` = an aisle was found. A goal without `category` (with `signWords`) = word search. `nil` = nothing found, and is also what the runner sends on error.
  - Wiring: build the session with `ShoppingSession(catalog: catalog.aisles, destinations: catalog.destinations)`. This init is Flow-owned. `init(catalog:)` is kept and falls back to the §5.6 keywords.
- **Why:** The frozen contract doesn't say any of this. If a side assumes differently, timers, listening or the entrance bearing break without any error.
- **Affects:** Wave 3 SessionRunner, Perception, Voice.
- **Local workaround:** Implemented as listed. The same notes are in the header of `Flow/ShoppingSession.swift`.

## EntrancePick needs a clock position computed from intrinsics
- **Who:** Core-session
- **What:** Add `public var clock: Int?` and `public var cartCorralClock: Int?` to `EntrancePick` (optional, so the Codable decoding of the Gemini response is unchanged). The runner fills them with `clockPosition(degreesRight: Geometry.degreesRight(portraitX:intrinsics:sensorHeight:))` before it sends `.entrancePicked`.
- **Why:** The session only gets `x` (0…1 across the upright still) and has no Stream B intrinsics, so "Entrance at 1 o'clock." is only an estimate.
- **Affects:** Wave 3 runner (or Network), Core-session.
- **Local workaround:** `Geometry.degreesRight(portraitX:horizontalFOV:)` with a nominal 92° portrait FOV (`SessionTuning.stillHorizontalFOV`).

## Shelf distance event for "The shelf is about one step ahead."
- **Who:** Core-session
- **What:** Add `case shelfDistance(Float)` to `SessionEvent`: LiDAR meters to the shelf, sent while `StreamWork.shelfMode` is on, at most once per ~2 s.
- **Why:** §5.2 "Point at the shelf" calls for this line, but no event carries the distance.
- **Affects:** Safety or Perception (sender), Wave 3 runner, Core-session.
- **Local workaround:** None. The line isn't spoken yet; "Step back a little" still comes from `.positioning(.stepBack)`.

## SessionRunner: UI hooks (`UISessionDriving`)
- **Who:** UI
- **What:** Make `SessionRunner` conform to `ViewModels/UISessionDriving.swift` (`@MainActor protocol UISessionDriving: AnyObject`):
  - `func submitTypedRequest(_ text: String)`: treat the text as a finished transcript (route it → `.routed(_)`, or
    `.notUnderstood(noisy: false)`); if a recording is running, end it with this text (Simulator: `TypedVoiceInput.submit`).
  - `func inject(_ event: SessionEvent)`: handle the event as if a service produced it and perform the effects. For
    `.danger`, first call `feedback.danger("Obstacle", steer: .left)` as the safety lane would. The main screen also uses
    `inject(.routed(.command(.repeatLast)))` for the double-tap "repeat" on the last-message row.
  - `func speakScreenText(_ text: String)`: drag-to-hear (not used while VoiceOver runs); `.reply` priority, replaces the previous screen line.
  - `func speakWalkthrough(_ lines: [String])`: first launch and the setup "Play walkthrough" button; speak in order at `.reply`.
    On first launch the view model calls it just before `start()`, so hold the opening "What are you looking for?" + listen until it finishes.
  - `func apply(settings: UISettings)`: speech speed (`UISpeechSpeed.rate`, `AVSpeechUtterance.rate` scale) and voice
    (`voiceIdentifier`, nil = best English voice), units (meters/steps, for spoken distances), tones on/off, danger haptics
    on/off (default on), detail level (`Verbosity`, e.g. via a session event or state). Called at launch and on every change.
- **Why:** The frozen API (`start`, `volumeUp`, `volumeDown`, `screenTalkPressed`) can't drive the Simulator debug panel,
  speak the walkthrough, do drag-to-hear, or apply setup settings, and views/view models may not touch services (§3.1).
- **Affects:** Wave 3 runner (and Feedback/Voice for speech rate, voice, tones, haptics; Core-session if detail level becomes an event).
- **Local workaround:** `AppViewModel` casts `(runner as AnyObject) as? UISessionDriving`; without the conformance these
  actions do nothing and the debug panel says the runner doesn't accept input yet. Settings persist in `UISettingsStore` (UserDefaults).

## Debug overlay values (`UIDebugSnapshotSource`)
- **Who:** UI
- **What:** Adopt `ViewModels/UIDebugSnapshot.swift`'s `protocol UIDebugSnapshotSource: AnyObject { var debugSnapshot: UIDebugSnapshot { get } }`
  on any of `SessionRunner`, `SafetyService`, `PerceptionService`, `FeedbackOutput`, `ObjectDetector` implementations.
  Safety fills corridor nearest/points, closing speed, TTC, steer, left/right lane clear, stairs; Perception fills YOLO
  detections, OCR text boxes, hand point and optionally the upright 0.5× frame (`preview`); Feedback fills `speechQueue`.
  Read ~2 Hz on the main thread while the overlay is open: must be thread-safe and cheap. Sources are merged (first non-empty wins).
- **Why:** §6 debug overlay needs these values; no contract exposes them.
- **Affects:** Wave 3, Safety, Perception, Feedback.
- **Local workaround:** Overlay shows "–" for missing values; capture preview/heatmap/costs come from `CaptureControl`.

## App root unchanged
- **Who:** UI
- **What:** None. `DigiFinderApp` keeps `AppViewModel(env: .current())` + `MainView(model:)`; `MainView` presents
  `SetupView` (sheet; opens by itself on first launch), `DebugOverlayView` (full screen) and, when
  `capabilities.cameraAvailable` is false, `CameraUnavailableView` (debug panel in the Simulator).
- **Why:** For Wave 3's reference.
- **Affects:** —
- **Local workaround:** —

## FrameSource: capability changes, thermal/rate hooks, debug snapshots
- **Who:** Capture
- **What:** Add to `FrameSource` (or make `AppEnvironment.frames` a `FrameSource & CaptureControl`) the members of
  `Capture/CaptureControl.swift`: `var onCapabilitiesChange: ((CaptureCapabilities) -> Void)?`,
  `func setThermalLevel(_: ThermalLevel)`, `func setRates(_: CaptureRates)`, `var rates: CaptureRates { get }`,
  `func makeStreamB() -> AsyncStream<FrameB>`, and the read-only debug members (`debugInfo`, `latestDepthSummary`,
  `latestDebugImage`, `latestDepthHeatmap`, `debugOverlayEnabled`).
- **Why:** `start()` returns at once and configures/asks permission on a background queue, so a denial or a failed
  configuration shows up later; the runner needs a callback to send `SystemEvent.cameraDenied` when
  `capabilities.cameraAvailable` turns false. `start()` also throws `CaptureError.denied` if permission is already denied.
  §5.16 thermal throttling needs a way to lower capture rates (the camera's own system pressure is applied automatically).
- **Affects:** Wave 3 runner (`.thermal(level)` → `setThermalLevel`; capability callback → `.system(.cameraDenied)`), UI debug overlay.
- **Local workaround:** `protocol CaptureControl` adopted by `MultiCamService`, `FallbackCameraService`, `NoCameraSource`;
  use `(env.frames as? CaptureControl)`.

## FrameSource.streamB is single-consumer
- **Who:** Capture
- **What:** Document `streamB` as one consumer only, or replace it with `func makeStreamB() -> AsyncStream<FrameB>`
  (each call a new `bufferingNewest(1)` subscription).
- **Why:** An `AsyncStream` traps or splits elements when two tasks iterate it. If both Safety (YOLO labels) and
  Perception iterate `frames.streamB`, the app breaks.
- **Affects:** Safety, Perception, Wave 3.
- **Local workaround:** `CaptureControl.makeStreamB()` already fans the same frames out to extra subscribers.

## DepthProvider.distance(at:) point space
- **Who:** Capture
- **What:** Doc comment only: `p` is a point of Stream B's upright portrait image (the only camera image perception
  sees); the result is meters along the viewing ray (median of a 5×5 depth window), nil outside the LiDAR field of view.
- **Why:** The LiDAR depth covers the 1× field of view, about half of the 0.5× image; mapping needs Stream B intrinsics.
- **Affects:** Perception (door/shelf distances), Safety.
- **Local workaround:** `LiDARDepthProvider(calibration:)` reads the latest Stream B intrinsics from a shared
  `CaptureCalibration` that the frame source updates; `CaptureFactory.makeBest()` wires both. Without it a nominal 2× zoom is used.

## Capture initializers and live wiring
- **Who:** Capture
- **What:** `AppEnvironment.live()` should use `let (frames, depth) = CaptureFactory.makeBest()` (LiDAR+ultra-wide →
  ultra-wide → wide → `NoCameraSource`). Init changes: `MultiCamService(lidar:ultraWide:calibration:)` or failable
  `MultiCamService(calibration:)`; `FallbackCameraService(device:calibration:)` or failable `FallbackCameraService(calibration:)`.
  Unchanged: `NoCameraSource()`, `LiDARDepthProvider()`, `EstimatedDepthProvider()`.
- **Why:** The stub inits had no devices; the factory keeps device choice in Capture.
- **Affects:** Wave 3 (`App/AppEnvironment.swift`).
- **Local workaround:** none needed; current `AppEnvironment` still compiles.

## Request.products needs a GoalChange
- **Who:** Core-logic
- **What:** `Request.products([Goal])` → `case products([Goal], GoalChange)` in `Contracts/Requests.swift`.
  The router fills it like `.product` ("actually coffee and milk" → `.replace`, "also coffee and milk" → `.add`, bare → `.unspecified`).
- **Why:** with no change slot, "actually coffee and milk" can't say "replace the current goal with both", and "also coffee and milk"
  can't be told apart from a fresh list, so the session has to guess.
- **Affects:** Core-session (`ShoppingSession` handling of `.routed(.products)`), Wave 3 runner. `RouterTests`' `case .products?:` pattern
  still compiles unchanged.
- **Local workaround:** `RequestRouter.routeWithChange(_:) -> RoutingResult` returns the request plus the implied `GoalChange`
  (`RequestRouter.goalChange(_:)` is also public). The runner can call it instead of `route(_:)` until the contract changes.

## VoiceInput: permission denial and recognition hints
- **Who:** Voice-Feedback-Network-System
- **What:** Add to `VoiceInput` the members of `Voice/VoiceInputControl.swift`: `var onPermissionDenied: (() -> Void)?`
  (main queue), `var permissionDenied: Bool { get }`, `func requestPermissions() async -> Bool`,
  `var contextualStrings: [String] { get set }`. (Alternative for denial: `VoiceResult.denied`.)
- **Why:** `listen` can only return `.empty`/`.cancelled`, so the runner can't tell a mic/speech denial apart from
  silence and can't send `.system(.micDenied)` (§5.16). Brand hints (§9 `contextualStrings`) have no setter.
- **Affects:** Wave 3 runner: `(env.voice as? VoiceInputControl)?.onPermissionDenied = { handle(.system(.micDenied)) }`,
  call `requestPermissions()` at start, set `contextualStrings` from catalog/database brand names.
- **Local workaround:** `SpeechVoiceInput` and `TypedVoiceInput` adopt `VoiceInputControl`; a denied listen returns `.empty(noisy: false)`.

## FeedbackOutput: vibration-only danger repeat and setup controls
- **Who:** Voice-Feedback-Network-System
- **What:** Add to `FeedbackOutput` the members of `Feedback/FeedbackControl.swift`: `func dangerVibrationOnly()`
  (re-alert a still-present obstacle without repeating the line), `var verbosity: Verbosity` (narration dropped at brief),
  `var speechRate: Float`, `var tonesEnabled: Bool`, `var dangerHapticsEnabled: Bool` (§5.13 setup).
- **Why:** the frozen protocol has no way to repeat only the vibration or to apply setup choices.
- **Affects:** Safety (optional repeat), Wave 3 runner / Setup sheet.
- **Local workaround:** `(env.feedback as? FeedbackControl)`; `SpeechFeedback` adopts it.

## Speech/listening behavior notes (doc only)
- **Who:** Voice-Feedback-Network-System
- **What:** (1) `VoiceInput.listen` itself does "wait for speech to end (max ~3 s) → hold guidance → beep → record";
  the session/runner must not emit `.chime(.beep)` before `.listen` (double beep). (2) `FeedbackOutput.stopSpeech()`
  stops and clears lines below stairs only; it never cuts a danger or stairs line (§5.10). (3) While the mic is open,
  `say` lines below stairs are held and played after the recording if still < 3 s old. (4) `chime(.done)` waits for the
  line in progress. (5) A second `listen` while one runs returns `.cancelled` immediately.
- **Why:** the protocol comments don't say who beeps or what `stopSpeech` keeps.
- **Affects:** Core-session (effects around `.listen`), Wave 3 runner.
- **Local workaround:** none needed.

## MotionService / SystemMonitor / Network semantics (doc only)
- **Who:** Voice-Feedback-Network-System
- **What:** `MotionService.yawDegrees` = back-camera heading around vertical, degrees, counterclockwise positive (CoreMotion
  sign; Core dead reckoning takes `-yawDegrees`), -180...180, arbitrary zero. `rotationRate` = magnitude of the gyro
  vector (rad/s). `SystemMonitor.onEvent` fires on the main queue; `.backgrounded` also fires for audio interruptions
  (call, Siri), `.foregrounded` when active again. Network: `NetworkJPEG.encode(_:)` makes the upright ~2000 px JPEG 0.8
  for `ask`/`pickEntrance`; errors are `NetworkError` (`.timeout`, `.offline`, `.rateLimited` = OFF 10/min hit, not sent).
- **Why:** sign/units and threads aren't stated in the protocols.
- **Affects:** Safety, Perception, Wave 3 runner.
- **Local workaround:** none needed.

## FrameSource: capability changes, thermal/rate hooks, debug snapshots
- **Who:** Capture
- **What:** Add to `FrameSource` (or make `AppEnvironment.frames` a `FrameSource & CaptureControl`) the members of
  `Capture/CaptureControl.swift`: `var onCapabilitiesChange: ((CaptureCapabilities) -> Void)?`,
  `func setThermalLevel(_: ThermalLevel)`, `func setRates(_: CaptureRates)`, `var rates: CaptureRates { get }`,
  `func makeStreamB() -> AsyncStream<FrameB>`, and the read-only debug members (`debugInfo`, `latestDepthSummary`,
  `latestDebugImage`, `latestDepthHeatmap`, `debugOverlayEnabled`).
- **Why:** `start()` returns at once and configures/asks permission on a background queue, so a denial or a failed
  configuration shows up later; the runner needs a callback to send `SystemEvent.cameraDenied` when
  `capabilities.cameraAvailable` turns false. `start()` also throws `CaptureError.denied` if permission is already denied.
  §5.16 thermal throttling needs a way to lower capture rates (the camera's own system pressure is applied automatically).
- **Affects:** Wave 3 runner (`.thermal(level)` → `setThermalLevel`; capability callback → `.system(.cameraDenied)`), UI debug overlay.
- **Local workaround:** `protocol CaptureControl` adopted by `MultiCamService`, `FallbackCameraService`, `NoCameraSource`;
  use `(env.frames as? CaptureControl)`.

## FrameSource.streamB is single-consumer
- **Who:** Capture
- **What:** Document `streamB` as one consumer only, or replace it with `func makeStreamB() -> AsyncStream<FrameB>`
  (each call a new `bufferingNewest(1)` subscription).
- **Why:** An `AsyncStream` traps or splits elements when two tasks iterate it. If both Safety (YOLO labels) and
  Perception iterate `frames.streamB`, the app breaks.
- **Affects:** Safety, Perception, Wave 3.
- **Local workaround:** `CaptureControl.makeStreamB()` already fans the same frames out to extra subscribers.

## DepthProvider.distance(at:) point space
- **Who:** Capture
- **What:** Doc comment only: `p` is a point of Stream B's upright portrait image (the only camera image perception
  sees); the result is meters along the viewing ray (median of a 5×5 depth window), nil outside the LiDAR field of view.
- **Why:** The LiDAR depth covers the 1× field of view, about half of the 0.5× image; mapping needs Stream B intrinsics.
- **Affects:** Perception (door/shelf distances), Safety.
- **Local workaround:** `LiDARDepthProvider(calibration:)` reads the latest Stream B intrinsics from a shared
  `CaptureCalibration` that the frame source updates; `CaptureFactory.makeBest()` wires both. Without it a nominal 2× zoom is used.

## Capture initializers and live wiring
- **Who:** Capture
- **What:** `AppEnvironment.live()` should use `let (frames, depth) = CaptureFactory.makeBest()` (LiDAR+ultra-wide →
  ultra-wide → wide → `NoCameraSource`). Init changes: `MultiCamService(lidar:ultraWide:calibration:)` or failable
  `MultiCamService(calibration:)`; `FallbackCameraService(device:calibration:)` or failable `FallbackCameraService(calibration:)`.
  Unchanged: `NoCameraSource()`, `LiDARDepthProvider()`, `EstimatedDepthProvider()`.
- **Why:** The stub inits had no devices; the factory keeps device choice in Capture.
- **Affects:** Wave 3 (`App/AppEnvironment.swift`).
- **Local workaround:** none needed; current `AppEnvironment` still compiles.

## Request.products needs a GoalChange
- **Who:** Core-logic
- **What:** `Request.products([Goal])` → `case products([Goal], GoalChange)` in `Contracts/Requests.swift`.
  The router fills it like `.product` ("actually coffee and milk" → `.replace`, "also coffee and milk" → `.add`, bare → `.unspecified`).
- **Why:** with no change slot, "actually coffee and milk" can't say "replace the current goal with both", and "also coffee and milk"
  can't be told apart from a fresh list, so the session has to guess.
- **Affects:** Core-session (`ShoppingSession` handling of `.routed(.products)`), Wave 3 runner. `RouterTests`' `case .products?:` pattern
  still compiles unchanged.
- **Local workaround:** `RequestRouter.routeWithChange(_:) -> RoutingResult` returns the request plus the implied `GoalChange`
  (`RequestRouter.goalChange(_:)` is also public). The runner can call it instead of `route(_:)` until the contract changes.

## FeedbackOutput: vibration-only danger repeat
- **Who:** Safety
- **What:** Add `func dangerPulse()` to `FeedbackOutput`: the danger vibration pattern only (no speech, speech already
  playing is left alone), callable from any thread.
- **Why:** §5.3 alert step 5: "Still closing ~2 s later → vibrations once more (no speech)". `danger(_:steer:)` always
  speaks the line again, and nothing else in the contract vibrates.
- **Affects:** Feedback (`SpeechFeedback` → `HapticsService.dangerPulse()`), Safety.
- **Local workaround:** `Safety/SafetyPulseOutput.swift` (`protocol SafetyPulseOutput { func dangerPulse() }`); Safety calls
  `(feedback as? SafetyPulseOutput)?.dangerPulse()`. Until a feedback type adopts it, the repeat is skipped.

## CaptureControl: Stream B calibration for Safety labels
- **Who:** Safety
- **What:** Add `var streamBCalibration: CaptureCalibration.StreamB? { get }` (latest Stream B intrinsics + buffer size)
  to `CaptureControl` (or to `FrameSource`).
- **Why:** §5.3 step 6 projects the nearest LiDAR points into Stream B to pick the YOLO box. Safety must not iterate
  `streamB` (Perception owns it), so it never sees `FrameB.intrinsics`.
- **Affects:** Capture, Safety (Perception could use it too).
- **Local workaround:** `Safety/SafetyStreamBLens.swift` reads `(frames as? CaptureSessionSource)?.calibration`; without it,
  the depth intrinsics with the nominal 2× field-of-view ratio `LiDARDepthProvider` also assumes.

## SafetyService: debug snapshot for the overlay
- **Who:** Safety
- **What:** Add `var debugSnapshot: SafetyDebugSnapshot { get }` to `SafetyService` (type in `Safety/SafetyDebugSnapshot.swift`:
  source, corridor distance/points, obstacle x, closing speed, TTC, steer, emergency, label + YOLO box + projected points,
  alert state, frame → haptic latency, ms per frame, floor height, stairs reading, stairs profile bins, `lines`).
- **Why:** §6 debug overlay shows corridor, steer lanes, TTC and the stairs profile; the contract has no read access.
- **Affects:** UI (debug overlay), Wave 3.
- **Local workaround:** `protocol SafetyDebugSource`; read `(env.safety as? SafetyDebugSource)?.debugSnapshot`
  (thread-safe copy; poll at ~2–5 Hz).

## SessionEvent.stairs: first sighting vs. "1 meter ahead"
- **Who:** Safety
- **What:** Add `case stairsNear(StairsObservation)` to `SessionEvent` (or document `.stairs` as below). Safety sends at most
  two stairs events per staircase: the first confirmed sighting → `stairsAnnouncement(obs)` ("Stairs going up, about
  8 steps, 3 meters, 12 o'clock."), then one at ≤ 1.2 m (LiDAR, or the pedometer countdown) → `stairsNearAnnouncement()`.
  No second event when the first sighting is already ≤ 1.2 m. Direction is always 12 o'clock (the profile looks ahead).
- **Why:** `StairsObservation` has nothing that tells the two apart.
- **Affects:** Core-session (`ShoppingSession` stairs lines), Wave 3.
- **Local workaround:** Safety sends both as `.stairs(obs)`; the session can treat a `.stairs` with distance ≤ 1.2 m that
  follows one with the same `up` as the near update.

## FrameSource.onDepth is shared; SafetyService.onEvent thread
- **Who:** Safety
- **What:** Doc comments only. `onDepth`: every consumer chains (`let previous = frames.onDepth; frames.onDepth = { f in
  mine(f); previous?(f) }`) and never replaces it. `SafetyService.onEvent`: called on the safety lane (the capture depth
  queue, or Safety's own queue for the no-LiDAR fallback); the handler hops to the main actor itself.
- **Why:** a plain assignment would silently turn danger detection off; the runner must not assume the main thread.
- **Affects:** Perception, Wave 3 runner: call `safety.start()` after `perception.start()` so Safety's closure is the
  outermost and its work runs first (haptic budget < 50 ms).
- **Local workaround:** `SafetyController.start()` chains as above and is idempotent.

## FrameSource: capability changes, thermal/rate hooks, debug snapshots
- **Who:** Capture
- **What:** Add to `FrameSource` (or make `AppEnvironment.frames` a `FrameSource & CaptureControl`) the members of
  `Capture/CaptureControl.swift`: `var onCapabilitiesChange: ((CaptureCapabilities) -> Void)?`,
  `func setThermalLevel(_: ThermalLevel)`, `func setRates(_: CaptureRates)`, `var rates: CaptureRates { get }`,
  `func makeStreamB() -> AsyncStream<FrameB>`, and the read-only debug members (`debugInfo`, `latestDepthSummary`,
  `latestDebugImage`, `latestDepthHeatmap`, `debugOverlayEnabled`).
- **Why:** `start()` returns at once and configures/asks permission on a background queue, so a denial or a failed
  configuration shows up later; the runner needs a callback to send `SystemEvent.cameraDenied` when
  `capabilities.cameraAvailable` turns false. `start()` also throws `CaptureError.denied` if permission is already denied.
  §5.16 thermal throttling needs a way to lower capture rates (the camera's own system pressure is applied automatically).
- **Affects:** Wave 3 runner (`.thermal(level)` → `setThermalLevel`; capability callback → `.system(.cameraDenied)`), UI debug overlay.
- **Local workaround:** `protocol CaptureControl` adopted by `MultiCamService`, `FallbackCameraService`, `NoCameraSource`;
  use `(env.frames as? CaptureControl)`.

## FrameSource.streamB is single-consumer
- **Who:** Capture
- **What:** Document `streamB` as one consumer only, or replace it with `func makeStreamB() -> AsyncStream<FrameB>`
  (each call a new `bufferingNewest(1)` subscription).
- **Why:** An `AsyncStream` traps or splits elements when two tasks iterate it. If both Safety (YOLO labels) and
  Perception iterate `frames.streamB`, the app breaks.
- **Affects:** Safety, Perception, Wave 3.
- **Local workaround:** `CaptureControl.makeStreamB()` already fans the same frames out to extra subscribers.

## DepthProvider.distance(at:) point space
- **Who:** Capture
- **What:** Doc comment only: `p` is a point of Stream B's upright portrait image (the only camera image perception
  sees); the result is meters along the viewing ray (median of a 5×5 depth window), nil outside the LiDAR field of view.
- **Why:** The LiDAR depth covers the 1× field of view, about half of the 0.5× image; mapping needs Stream B intrinsics.
- **Affects:** Perception (door/shelf distances), Safety.
- **Local workaround:** `LiDARDepthProvider(calibration:)` reads the latest Stream B intrinsics from a shared
  `CaptureCalibration` that the frame source updates; `CaptureFactory.makeBest()` wires both. Without it a nominal 2× zoom is used.

## Capture initializers and live wiring
- **Who:** Capture
- **What:** `AppEnvironment.live()` should use `let (frames, depth) = CaptureFactory.makeBest()` (LiDAR+ultra-wide →
  ultra-wide → wide → `NoCameraSource`). Init changes: `MultiCamService(lidar:ultraWide:calibration:)` or failable
  `MultiCamService(calibration:)`; `FallbackCameraService(device:calibration:)` or failable `FallbackCameraService(calibration:)`.
  Unchanged: `NoCameraSource()`, `LiDARDepthProvider()`, `EstimatedDepthProvider()`.
- **Why:** The stub inits had no devices; the factory keeps device choice in Capture.
- **Affects:** Wave 3 (`App/AppEnvironment.swift`).
- **Local workaround:** none needed; current `AppEnvironment` still compiles.

## Request.products needs a GoalChange
- **Who:** Core-logic
- **What:** `Request.products([Goal])` → `case products([Goal], GoalChange)` in `Contracts/Requests.swift`.
  The router fills it like `.product` ("actually coffee and milk" → `.replace`, "also coffee and milk" → `.add`, bare → `.unspecified`).
- **Why:** with no change slot, "actually coffee and milk" can't say "replace the current goal with both", and "also coffee and milk"
  can't be told apart from a fresh list, so the session has to guess.
- **Affects:** Core-session (`ShoppingSession` handling of `.routed(.products)`), Wave 3 runner. `RouterTests`' `case .products?:` pattern
  still compiles unchanged.
- **Local workaround:** `RequestRouter.routeWithChange(_:) -> RoutingResult` returns the request plus the implied `GoalChange`
  (`RequestRouter.goalChange(_:)` is also public). The runner can call it instead of `route(_:)` until the contract changes.

## PerceptionService: remember(_:) and debug snapshot
- **Who:** Perception
- **What:** Add to `PerceptionService`: `func remember(_ p: ProductInfo)` (saves the last confirmed held-item label crop to
  `ProductMemory.save(_:crop:)`), and optionally `var debugSnapshot: PerceptionDebugSnapshot { get }` (latest YOLO boxes,
  OCR regions, signs, hand tip + pointed spot, pointed/target regions, doors, rates, held label/barcode, last event).
- **Why:** `Effect.remember(ProductInfo)` needs the label crop, which only Perception has (§5.14). The debug overlay (§6)
  needs boxes, OCR regions and the hand point.
- **Affects:** Wave 3 runner (`Effect.remember` → `remember`), UI debug overlay.
- **Local workaround:** both exist on `PerceptionController`; use `(env.perception as? PerceptionController)?.remember(p)`
  and `.debugSnapshot`.

## Perception event semantics (no signature change)
- **Who:** Perception
- **What:** How Perception fills the existing events, for Core-session and the runner:
  - `.signs([AisleSign])`: on change (≤ 4/s) and every ~3 s while signs stay in view; `.signs([])` once when they vanish (~1.5 s).
  - `.doors([DoorObservation])`: nearest first, on change and every ~2 s while doors are in view; `.doors([])` once when they vanish.
    Sent whenever YOLO sees a door (any step except pointing/hold-up); the flow ignores it outside the entrance step.
  - `.aisleVerdict(aisle, evidence:)`: only when the verdict changes to a new non-nil aisle; the vote resets on `setTarget`,
    when text work turns on, and after `.arrivedAtAisle`.
  - `.arrivedAtAisle(clock:)` / `.arrivedAtDestination`: once per target sign (dead reckoning; needs `MotionService` started
    by the runner/environment, Perception never calls `motion.start()`).
  - `.pointed(p)`: ≤ 1/s, on change or every ~3 s. `PointedProduct(text: "", match: 0, directionToTarget: dir)` = nothing
    readable at the fingertip but the target is in view; `.pointed(nil)` = nothing readable and no target in view.
  - `.confirmed(nil, isGoal: false)`: hold-up still unclear for ~4 s (then every ~4 s), for "Turn it slowly." /
    "Try holding it a little farther away." A found product repeats at most every ~4 s.
  - `.outside(Bool)`: changes only; default inside.
  - `.positioning(hint)`: §5.8 except `.phoneFlipped` (Safety), ≥ 4 s apart, the same hint ≥ 10 s apart.
  - Events are sent from Perception's queues, never the main thread.
- **Why:** The frozen contract fixes the cases but not when they fire or what nil/empty means.
- **Affects:** Core-session (`ShoppingSession`), Wave 3 runner.
- **Local workaround:** none needed.

## OIV7 spelling: "Doughnut", not "Donut"
- **Who:** Perception
- **What:** Doc fix in implementation_plan.md §2: the exported yolov8s-oiv7 model's label is "Doughnut" (601 classes;
  checked from the model metadata). `categories.json` lists "Donut".
- **Why:** Exact-name matching would drop the class from the visual vote.
- **Affects:** Data / tools (optional: change `aisle_map.json` to "Doughnut"), Safety if it matches labels by name.
- **Local workaround:** `ObjectDetectionService.resolve(_:in:)` maps catalog names to model labels (exact → case-insensitive
  → aliases such as Donut ↔ Doughnut); `PerceptionController` validates every `visualClasses` entry at load and logs the rest.

## Thermal caps: Perception doesn't call CaptureControl.setRates
- **Who:** Perception
- **What:** Note only. `CaptureControl.setRates` holds one value (last writer wins), so Perception caps its own work from
  `StreamWork.yoloFPS` (YOLO at that rate; OCR/hand pose scaled down with it) instead of calling it.
- **Why:** Two modules calling `setRates` would overwrite each other's caps.
- **Affects:** Wave 3 runner (thermal: lower `yoloFPS` in `setWork` and call `setThermalLevel` on the frame source).
- **Local workaround:** none needed.
