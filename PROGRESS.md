# PROGRESS

Read this first after a restart or compaction, then continue from "Next".

## Working rules (from the owner)
- **Never `git commit`** (subagents included). The owner reviews and commits in Xcode. At the end of each phase,
  give them a suggested commit message (summary + description) with no AI attribution lines.
- **No AI-tool attribution or mentions** anywhere in the repo or in suggested commit messages. Before the owner pushes,
  search the repo (excluding `.git`, `.venv`, `build_out`, `.build`) for the assistant's name and scrub hits.
- Because nothing is committed by agents, Wave 2 can't merge agent branches. Each agent works in a
  **directory copy** of the working tree at `$SCRATCH/df-<name>` (scratchpad, outside ~/Desktop: copies there would sit in the
  lab1 repo and Desktop metadata breaks Simulator codesign), made with rsync excluding `.git`, `.venv`, `build_out`, `.build`,
  `.swiftpm`, `xcuserdata`. Agents build with derived data `~/Library/Developer/Xcode/DerivedData/df-<name>` and never commit
  (copies have no .git). The orchestrator rsyncs back only the agent's owned folders and appends its CONTRACT_CHANGES.md entries.
  If the scratchpad is gone after a restart, re-create copies from the main tree.

## Naming and setup decisions
- The app is **DigiFinder** (renamed from Item Finder at the owner's request). `implementation_plan.md` was updated:
  `ItemFinder` → `DigiFinder`, `ItemFinderCore` → `DigiFinderCore`, scheme `DigiFinder`, resources in `DigiFinder/Resources/`.
- Repo root: `~/Desktop/Birdbox` (git remote `https://github.com/Qiaojuno/StormHacks2026-DigiFinder.git`).
  `~/Desktop` itself is a separate repo (lab1); never run git from there.
- Docs live at the repo root (`prd.md`, `implementation_plan.md`), outside the synchronized app folder so they aren't bundled.
  Ignore the older copies on `~/Desktop`.
- `xcode-select` points at Command Line Tools: run every `xcodebuild`/`swift` with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Project settings (set by editing project.pbxproj at the owner's request in Phase 0): iOS 17.2, Swift 5, iPhone only,
  portrait only, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (Xcode 26 defaults to MainActor, which would pull the safety
  lane onto the main thread), `MemberImportVisibility` upcoming feature on (import every module you use in each file),
  four `INFOPLIST_KEY_NS…UsageDescription` keys, display name DigiFinder, bundle id `nick.DigiFinder`.
  Background mode `audio` lives in `DigiFinder/Info.plist` (Xcode-managed, excluded from target membership).
  Template SwiftData/CloudKit code, entitlements and the template test targets were removed. Shared scheme added.
- The owner has the project open in Xcode: don't hand-edit project.pbxproj while it's open.

## Wave 1 decisions (contracts are frozen after the owner reviews Wave 1)
- Contracts: `DigiFinderCore/Sources/DigiFinderCore/Contracts/` (Spatial, Products, Observations, Requests, Session) and
  `DigiFinder/Protocols/` (CaptureProtocols, ServiceProtocols). Every public struct has a public init with defaults.
  `AisleInfo` decodes missing keys as empty lists.
- `SessionState` and `ShoppingSession` live in `Flow/` (owned by Core-session, free to grow). The runner relies on
  `state.step`, `state.lastLine`, `state.isWalking`. Stub: `.started` → "What are you looking for?" + listen.
- Real code already in Core: RequestRouter (+ VoiceCommandParser phrase table), matching (normalizeText, normalizeBarcode,
  levenshtein, fuzzyContains, score, confirmFromLabel, isPriceTag, AisleVote), geometry (Vec3/Mat3/NormRect helpers,
  `Geometry.fromVision`, `Geometry.fromSensorPixels`/`toSensorPixels`, `Geometry.degreesRight`, Corridor, isEmergency,
  steerDirection, alertPhrase, detectStairs, clockPosition), SpeechPriorityQueue. Tests: RouterTests (all rows pass) + CoreBasicsTests.
- Real code in the app: `Capture/CameraGeometry.swift` (intrinsics scaling, unproject, project to Stream B, leveling with
  gravity, camera↔device axes), `Voice/CaptureEventView.swift` (§9 snippet), `Network/NetworkSecrets.swift`,
  `Capture` `FrameScheduler`, `AppEnvironment` wiring with stubs, `AppViewModel` (§6), MVP `MainView` stub.
- Everything else is a compiling stub in `<Folder>/<Folder>Stubs.swift`. Wave 2 agents replace stubs with one file per
  type and delete the stub file (keep the type names and inits AppEnvironment uses, or note the change for Wave 3).
- `DeviceMotionService` (MotionService) lives in `System/` → Voice-Feedback-Network-System agent owns it.
- Plan snippet fix: §6 `var showSetup = false, showDebug = false` doesn't compile under `@Observable`; split into two lines.
- Type-check the app without Xcode (works before the package is linked): build DigiFinderCore for the Simulator with
  `xcodebuild -scheme DigiFinderCore -destination 'generic/platform=iOS Simulator' -derivedDataPath <dd>` inside
  `DigiFinderCore/`, then `xcrun swiftc -typecheck -parse-as-library -swift-version 5 -sdk $(xcrun --sdk iphonesimulator --show-sdk-path)
  -target arm64-apple-ios17.2-simulator -enable-upcoming-feature MemberImportVisibility -I <dd>/Build/Products/Debug-iphonesimulator <all app .swift files>`.

## Data (Phase 2)
- `products.sqlite` (120,330 rows, 20.8 MB, Canada + US, aisles only) and `categories.json` built into `build_out/` and copied
  to `DigiFinder/Resources/`. No `demo_barcodes.txt` exists, so `--check` was skipped.
- `yolov8s-oiv7.mlpackage` exported and copied to `DigiFinder/Resources/`. coremltools has no Python 3.14 build
  ("BlobWriter not loaded"), so the export ran in `build_out/yolo/venv39` (system Python 3.9). `.venv` (3.14) has duckdb + huggingface_hub.
- `products.sqlite`, `*.mlpackage`, `Secrets.plist` are gitignored; `categories.json` and `synonyms.json` are committed.
- `Secrets.example.plist` uses `gemini-2.5-flash` as the model placeholder; that model is retired for new keys — use `gemini-3.8-flash` (verified 2026-10-04).

## Build check
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd DigiFinderCore && swift test)
xcodebuild -scheme DigiFinder -destination 'generic/platform=iOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/DigiFinder-cli CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme DigiFinder -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/DigiFinder-cli build
```

## Phases
- [x] **Phase 0: setup.** Project fixed and renamed; both xcodebuild checks green (placeholder app).
- [x] **Phase 1: Wave 1 done.** Package added by the owner; all three build checks green. Contracts frozen.
  Derived data must live outside ~/Desktop (Desktop file metadata breaks Simulator codesign: "detritus not allowed").
- [x] Phase 2: data jobs done (see Data).
- [x] **Phase 3: Wave 2 done.** All 8 modules merged (Capture, Core-logic, Data, Core-session, UI, Voice-Feedback-Network-System,
  Safety, Perception). No stubs left. `swift test` 150/150, device + Simulator builds green.
  - Integration notes from agents (all detailed in CONTRACT_CHANGES.md):
    - `AppEnvironment.live()` must use `CaptureFactory.makeBest()`; runner must call `motion.start()`, `perception.start()` then
      `safety.start()` (Safety's depth work runs first), map capability/mic denial to SystemEvents, `.tick` = absolute monotonic clock.
    - `listen()` plays its own beep: the session/runner must not add `.chime(.beep)` before `.listen`.
    - Safety's 2 s vibration-only repeat needs Feedback to adopt `SafetyPulseOutput` (Feedback added a vibrate-only call too).
    - Perception: `remember(_:)` for Effect.remember; real model label is "Doughnut" (aliases mapped); don't call
      `describeSurroundings()` on the main thread.
    - UI: runner should adopt `UISessionDriving` (typed requests, debug events, walkthrough, settings, drag-to-hear);
      modules adopt `UIDebugSnapshotSource` for overlay values.
- [x] **Phase 4: Wave 3 done.** Contract changes applied (file cleared), SessionRunner, live/simulator wiring, README Setup. 158 tests, both builds green; Simulator launch + typed "coffee" verified by the agent.
- [x] **Phase 5 done.** Independent review: 9 bugs + 2 wording issues; fixed all but the customer-service desk distance (signs carry no distance). Owner changes: start prompts "Press volume up to tell me." instead of auto-listening; Simulator DF_TYPED_REQUEST hook removed. 161 tests, both builds green, Simulator launch OK. Next: owner phone testing (§8 acceptance, §10 verify). M9 not started.

## Wave 2 decisions given to agents
- Test ownership: Core-logic owns `RouterTests.swift`, `CoreBasicsTests.swift` and new `Matching*/Geometry*/Speech*/Routing*Tests.swift`;
  Core-session owns `SessionStartTests.swift` and new `Session*Tests.swift`.
- The session has no database: it emits `.setTarget(goal, candidates: [], destination:)`; the runner (Wave 3) fills the
  candidates from the database before calling perception.
- Data also provides the router's product search: a goal resolver (query → `[Goal]` with category from the database,
  brand/variant/form only from the user's words) and `candidates(for: Goal)`, falling back to `extraProducts` without the database.
- Capture also provides a factory that picks LiDAR+ultra-wide → ultra-wide → wide → unavailable and returns the matching
  FrameSource + DepthProvider, for `AppEnvironment.live()` (Wave 3).

## Next
1. When a batch-1 agent reports: rsync its owned folders back, append CONTRACT_CHANGES entries, run the build checks.
2. Then batch 2. Tell the owner when Capture + Safety are both in and building (phone danger test).
3. Phase 4 (Wave 3 integration), Phase 5 (review). Suggest a commit message to the owner after each phase.

## Owner changes after Phase 5 (2026-10-04)
- Danger = threat level, not proximity (`Geometry/GeometryThreat.swift`): only movers approaching (person, cart…) vibrate;
  chest/head-height overhangs are spoken only; everything else is the cane's job. 3-frame rule. Clock steering
  (`openHeading`), "stop. Turn slowly.", "Clear ahead, about N meters. Walk straight." (`SessionEvent.pathClear`),
  distances in alerts/doors/desks (`AisleSign.distance`). Stairs + flipped only while walking. Tilt prompts never.
  Model "Doughnut" renamed "Donut" at load. §5.3 / §5.8 updated.
- UI: Home = full-screen live 0.5× preview (`FrameSource.attachPreview`, explicit multi-cam preview connection) +
  camera-style record button + Home / Settings. Settings page holds setup, licenses and the debug overlay.
  Verify on device: multi-cam cost with the preview connection.
- Stairs down: the "floor ends, nothing beyond" rule is gone (shiny floors / grazing angle made it fire constantly);
  down now needs a sharp edge onto a visible lower surface AND YOLO "Stairs" within 1 s. Debug button top-right on Home.
- YOLO output filtered to an allowlist (`ObjectDetectionService.essentialLabels` + catalog visualClasses): people/movers,
  Door, Stairs, Shelf, Car/Tree/Street light (outside check). Everything else (Building, Office building…) is dropped
  after detection. All names verified against the exported model's 601 classes.
- Look first + nearby mode: every search starts in Step `.lookingNearby` (~5 s; signs hand over), `SessionEvent.itemSeen`
  from `PerceptionItemFinder` (YOLO class via `Goal.visualClass`, or goal label text), nearby mode (Settings toggle /
  "it's nearby" / "store mode") skips signs. Household objects (`MatchingHousehold`, 55 words → OIV7 classes, all in the
  allowlist) end at "within reach". Battery and heat lines removed (throttling stays silent). §5.2 / §5.16 updated.
- Shopping state machine refactor (2026-10-04): two layers. **Motion state** (Walking / Standing) = Core
  `Motion/MotionStateTracker` (1.5 s window of pedometer steps + user-acceleration spread, hysteresis, thresholds in
  `MotionTuning`, verify on device) inside `DeviceMotionService`; one source for Safety (`motion.isWalking`) and the
  session (`.motion(walking:)`); it alone decides alerts (threat-level rules; shelf mode deleted from StreamWork /
  Corridor / ThreatInput / DangerDetector / flip check). **Task phases** `Step`: idle, entrance, findAisle, inAisle,
  pick, confirm; Ask pending + background/lost pause are overlays. Item rule in every search phase (≤ 1.2 m ahead:
  Standing → Pick, Walking → "Stop. X at N o'clock." → Pick on Standing). Removed timers: look-first ~5 s, in-aisle
  ~4 s "turn to the shelf", 6 s turn fallback, turn-back not-found. Aisle end: Core `AisleEndTracker` in Safety →
  `.aisleEnd` (≥ 5 steps in aisle; pedometer backup 20 m). Place check at app open: 3 stills after a good-photo gate →
  Gemini `{grocery, confidence, scene}`, retry once < 0.7, place line before the opening question; `general` = anywhere
  else. Recording: volume up only starts, volume down only stops, no silence end / time limit, no auto-listen.
  Gemini assist replaces Ask: questions / unknown items / unmatched words go silently with a still + context →
  `{say, findItem}`. 195 Core tests; device + Simulator builds green. §2, §3.3, §5 updated.
- Flip camera (lanyards that hang upside down): top-left "Flip" on Home → Confirm/Cancel alert, read aloud; saved in
  settings. `Geometry.cameraUpsideDown` flips every sensor ↔ portrait mapping and left/right in Core;
  `CaptureOrientation` (app) drives Vision orientation (.right/.left), stills, debug images and the preview angle (90/270).
- Place default inverted: general unless Gemini says grocery (≥ 0.7) / store entrance / "store mode".
- Recording vs stream (owner decision): recording ends on silence (~1.5 s after speech, ~6 s if nothing said) and is routed;
  volume down / the stop button ends the STREAM: recording discarded, all speech cut, camera + danger + perception off,
  item and list cleared, silent (`SessionEvent.donePressed` → `Effect.setStreaming(false)`). Volume up restarts. A new
  item mid-search is added (no "Switch or add?").
- App opens stopped ("Press volume up to start."); the first volume up starts the stream + recording + the grocery
  check (once per app open; place line after the request). Freeze fix: AVAudioSession speak↔listen switches run on a
  serial background queue (`FeedbackAudioSession.switchQueue`); SpeechFeedback/ToneService getters no longer
  `queue.sync` from the main thread.
- Recording freeze fixes: cancelled recordings now send `.recordingCancelled` (session stopped waiting forever →
  volume up was ignored); 30 s stuck-recording safety net; capture sessions no longer manage the app audio session
  (`automaticallyConfiguresApplicationAudioSession = false`) and restart after interruptions/runtime errors (frozen
  preview while recording); record button always enabled (no walking guard).
- Camera always runs while the app is open (volume buttons need a running capture session; live view). Stopped = danger/perception/prompts off only.
- Gemini item finder (YOLO OIV7 + label OCR miss many items): while searching online (stream on, goal, Entrance /
  FindAisle / InAisle, no Ask pending), `Flow/SessionGeminiFinder` sends the latest Stream B frame (upright, 1024 px,
  JPEG 0.7) to `GeminiClient.findItem` ~every 2 s (one in flight; 4 s while tracking; 5 s back-off on 429 / 503 / errors,
  silent). Found (≥ 0.5) → `PerceptionService.trackTarget` → `Perception/PerceptionTargetTracker` (Vision object tracking)
  → normal `.itemSeen`; lost → ask at once. Not found → `SessionEvent.searchHint` (spoken as guidance when new, ≤ 1 per
  ~8 s, never while talking / Ask / stopped). Debug: "Gemini finder" note line + "Gemini target" box. Model
  `gemini-3.8-flash` with `thinkingLevel: low` (2.5-flash retired for new keys). Privacy wording §2 / §5.11 updated.
  Verify on device: tracker drift (the box is from a frame ~2 s old), cost/quota at ~20–30 requests/min.
- Place never announced: "Loading." while the check runs, then "Okay, now looking for <item>."
- One item at a time: a newly named item always replaces the current one (no list; several items → the first).
- Gemini is the only item finder (every ~2 s while searching, also while tracking). On-device item search is COMMENTED OUT
  in `PerceptionController` (text reading, signs, aisle vote, doors, pointing, hold-up label check, arrival, outside),
  and `SessionState.onDeviceItemSearch` is false in the app: every search is Gemini-guided and ends "within reach".
  YOLO allowlist = obstacle classes + Stairs only. Store-flow tests keep running with the flag on (harness `onDevice:`).
- Gemini finder photos 640 px / JPEG 0.6 (~1.6 s per answer vs 4–9 s at 1024 px); Gemini timeout 10 s. Key with $4 prepaid cap verified 2026-10-04.
- Gemini keys: `GeminiAPIKey` (main) + optional `GeminiFallbackAPIKey` in Secrets.plist. A refused key (401/402/403/429) falls back to the other for the same request and is skipped for 5 min (`NetworkKeyChooser`).
- Alert profiles by place (`ThreatProfile` in Core): grocery store = sensitive (old values); general (school, campus,
  unknown, the default) = calm: faster/closer approach needed, collision-course check from sideways speed, 5 frames,
  10 s cooldown, and with ≥ 4 people in view only alerts when contact is within 1 s. `SessionRunner` sets it from the
  place check / manual setting. Danger vibration is now one pulse everywhere. YOLO allowlist adds Table and Chair.
  Verify on device: crowded hallway (should stay quiet unless someone walks straight into you), store aisle with carts.
- Demo: table alerts (`TableAlertRule` in Core). While walking and YOLO sees a table (Table, Coffee table, Kitchen &
  dining room table, Desk, Billiard table), a lower corridor (down to ~0.55 m above the floor) is checked; a table in the
  path within 1.5 m for 3 frames → one vibration + "Table ahead, steer to N o'clock". No 2 s repeat buzz, no "Clear
  ahead", 20 s cooldown for any table. Standing still: never. To remove after the demo: the block in SafetyController.
- Gemini lines wait for alerts (owner decision): search hints and Ask answers that arrive during an alert are held
  (`SessionState.afterDanger`, newest hint only) and played when it clears; a new alert keeps them waiting; stop drops
  them. In speech, an alert no longer drops a reply that was playing or waiting: it replays after the alert(s).
  Guidance still goes stale as before.
- Demo: fences / barricades (`BarrierAlertRule`, LiDAR only: YOLO OIV7 has no fence/barricade/cone class). While
  walking: ≥ 5 of 7 10-cm columns across the path blocked at waist height (0.3 m above the floor to 0.2 m below the
  phone) within 1.5 m, nearly nothing above → one vibration + "Barrier ahead, steer to N o'clock", 20 s cooldown.
  Skipped for tables, stairs, and YOLO movers (carts). Verify on device: may fire on low shelf ends / counters.
- Tables buzz once from up to 3 m (was 1.5 m); table corridor reaches 3.5 m.
- Wet floor signs (owner decision; not an OIV7 class): on-device text reader (~1 Hz, walking only) finds "wet floor" /
  "caution" (+ Spanish / French) → `.wetFloorSign(clock:)` → one vibration (`Effect.buzz`) + "Wet floor sign, N o'clock."
  (stairs priority), 20 s cooldown. Needs the words readable (~2–3 m, facing the camera).
- Crowd warning: every Gemini item-finder scan also returns `crowded` (about 6+ people within a few meters) →
  `.crowded` → "Lot of people around you, be careful." as a reply, at most once per 60 s, held during alerts.
  Only while a search runs (that's when Gemini scans).
- After an item (found, not found, or stopped): no "What's next?" and no "Shopping done" follow-up. One line:
  "I couldn't find <item>." / "Got it…" then "Press volume up to look for something else." The stream stays on.
- Obstacle detection (YOLO, 10 fps) runs whenever the stream is on, in every phase incl. idle with no search
  (already true; locked by `DetectionAlwaysOnTests`).
- Table rule reworked (owner decision): while walking, a table in the path buzzes once at 0.8 m ("Table ahead, steer
  to N o'clock"), tracked from 1.5 m. If the tabletop drops below the chest camera's view (last seen ≤ 1.1 m,
  centered, within 1 s) it alerts then. One buzz per table: re-armed after 3 s with no table within 1.5 m. Standing
  still or turning fast: nothing (no tracking).
- Barrier fix (owner report: table seen, barricade missed): the barrier check no longer turns off whenever YOLO sees a
  table anywhere (only skips if the barrier itself is labeled a table / person / cart). Looser shape: 4 of 7 columns,
  2 pts per column, range 2 m, above-band allowance max(40, a quarter of the barrier's points). Debug overlay has a
  "barrier:" line (FOUND / n/7 columns / pts above (wall?) / not a line across / labeled X / standing …).
  Hardware limit: iPhone LiDAR is low resolution; thin see-through rails barely show up, solid panels do.
- Barrier buzz range 3 m (owner: 2 m was too late).
- Barrier alerts always give a clock direction: no fully open gap → the least blocked heading (the side with the most room) instead of "stop. Turn slowly." (`steerDirection(alwaysClock:)`).
- Buttons (owner decision): volume DOWN (bottom) starts the stream when stopped ("Started. Press volume up to tell me
  what to find.", runs the one-time place check) and stops everything when running. Volume UP (top) ONLY records a
  request; when stopped it says "Press volume down to start.". The on-screen red button = volume down. App opens with
  "Press volume down to start." Walkthrough line updated (and "one strong vibration").
- Main screen redesigned to the Figma (design only, no behaviour change): dark rounded bottom bar with Detect (the
  camera page, formerly Home) and Settings tiles, big red-orange record button on the bar's top edge (circle in a grey
  glass ring when stopped, orange square on glass while running; tap = volume down as before), big Flip tile top left,
  small round Debug button top right. Tokens in `UITheme` (brand #E2533A, bar #211816, glass). Reduce Motion respected.
  Plan §6 rewritten to match. Checked against the Figma in the iPhone 17 Pro Simulator (button ring ≈ 36% of width).
- Camera flip is automatic (owner decision): `OrientationTracker` (Core) reads gravity along the phone's long axis
  each runner tick; upside down (g.y > +0.5) or upright (< -0.5) held ~1 s sets `CaptureOrientation`, which every
  camera-image direction uses (Gemini photos and boxes, item tracker clock, signs, wet floor sign, YOLO label
  projection). The tracked box and any in-flight Gemini answer are dropped on a flip (`SessionGeminiFinder.restart`).
  LiDAR alerts were already gravity-based. Flip tile, confirm dialog and the `cameraUpsideDown` setting removed.
  Debug overlay shows "upright / UPSIDE DOWN (g.y …)". Verify on device: g.y ≈ -1 upright on the lanyard.
- Spoken-line rule (owner): ≤ 8 words per line, fewer is better, actionable only (§0). Every SessionPhrases line
  shortened (e.g. "Started. Volume up to ask.", "Volume up for another item.", "Coffee, within reach.", "Stairs up,
  about 8 steps, 3 meters."). Gemini prompts (item hint, Ask answer) ask for ≤ 8 actionable words and no scene
  narration; code enforces it: `capWords` cuts Gemini text to 8 words, hints with no direction word are dropped.
  Walkthrough lines shortened too. `PhraseLengthTests` fails if any line goes over 8 words.
- Search persistence (owner decision): in a grocery store (place check or manual setting) the Gemini-guided search
  never gives up; elsewhere still ~60 s → "I couldn't find X.". "Turn slowly." replaced: every ~15 s without a
  sighting → "Stop and look around. I need context."; after ~4 s standing still (≈ two Gemini scans) → "Keep going.";
  a sighting answers it instead; still walking after 20 s → asked again. Tests: SessionContextTests.
