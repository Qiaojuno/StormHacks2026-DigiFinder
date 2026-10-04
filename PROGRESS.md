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
- `Secrets.example.plist` uses `gemini-2.5-flash` as the model placeholder; confirm the current model name when filling `Secrets.plist`.

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
- [ ] Phase 3: Wave 2 (8 module subagents) — **in progress**
  - Batch 1 (running): Core-logic, Core-session, Capture, Data
    - Capture: **merged**, device + Simulator builds green. Adds `CaptureControl` (capability callback, thermal/rates,
      `makeStreamB()` fan-out, debug snapshots) and `CaptureFactory.makeBest()`. `streamB` is single-consumer and
      `onDepth` is a single closure: batch-2 agents must use `makeStreamB()` and chain onto `onDepth` (keep the previous
      handler; Safety's work runs first, Perception's handler only stores the latest frame).
    - Core-logic: **merged**, `swift test` 73/73 green. Adds `RequestRouter(…, synonyms:)` and `routeWithChange`
      (CONTRACT_CHANGES: `Request.products` needs a GoalChange), `SpeechPriorityQueue.enqueue`, clock/TTC/dead-reckoning helpers.
    - Data: **merged**, device + Simulator builds green. Adds `DataGoalResolver(products:catalog:)` with `goals(for:)`
      (router productSearch) and `candidates(for:limit:)`; `Catalog.synonyms`; `ProductMemory(directory:)`; hint threshold 0.4 (verify on device).
    - Core-session: **merged**. Full Core suite 150/150 green; device + Simulator builds green. `.tick` is an absolute
      monotonic clock (first tick = reference); runner rules in CONTRACT_CHANGES "Flow runtime semantics". Adds
      `ShoppingSession(catalog:destinations:)`. Own-wording lines to review: "Push door." / "Pull door.",
      "Okay, still looking for X.", "I can't see much around you.", mic-denied line.
  - Batch 2 (running): Safety, Perception, Voice-Feedback-Network-System (copies made after Capture/Core-logic/Data merges)
    and UI (copy made after Core-session merge). Notes they were briefed with:
    use `(frames as? CaptureControl)?.makeStreamB()` for Stream B and chain onto `frames.onDepth` (keep the previous handler);
    Perception owns YOLO (`ObjectDetectionService`), Safety only reads `detector.latest`; Safety also emits
    `.positioning(.phoneFlipped)` (max once per 30 s, not in shelf mode); Perception adds `remember(_ p: ProductInfo)` that saves
    the last confirmed crop to ProductMemory (runner calls it for `Effect.remember`); router search = `DataGoalResolver.goals(for:)`.
- [ ] Phase 4: Wave 3 integration
- [ ] Phase 5: review and hand-off

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
