# PROGRESS

Read this first after a restart or compaction, then continue from "Next".

## Working rules (from the owner)
- **Never `git commit`** (subagents included). The owner reviews and commits in Xcode. At the end of each phase,
  give them a suggested commit message (summary + description) with no AI attribution lines.
- **No AI-tool attribution or mentions** anywhere in the repo or in suggested commit messages. Before the owner pushes,
  search the repo (excluding `.git`, `.venv`, `build_out`, `.build`) for the assistant's name and scrub hits.
- Because nothing is committed by agents, Wave 2 can't merge agent branches. Plan: each agent works in a
  **directory copy** of the working tree (`../df-<name>`, made with rsync, excluding `.git`, `.venv`, `build_out`, `.build`),
  builds there, and does not commit; the orchestrator rsyncs back only the agent's owned folders and appends its
  CONTRACT_CHANGES.md entries.

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
- [ ] Phase 3: Wave 2 (8 module subagents)
- [ ] Phase 4: Wave 3 integration
- [ ] Phase 5: review and hand-off

## Next
1. Owner: File → Add Package Dependencies… → Add Local… → `DigiFinderCore` → add to target DigiFinder; review and commit.
2. Run the three build checks until green; then contracts are frozen.
3. Phase 3, batch 1: Core-logic, Core-session, Capture, Data (directory copies, no commits).
