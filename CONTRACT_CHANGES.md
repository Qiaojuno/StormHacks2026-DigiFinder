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
