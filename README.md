# StormHacks2026-DigiFinder

## Setup

### 1. Xcode project (already configured)
The project in this repo is already set up as in `implementation_plan.md` §4.0: SwiftUI app target `DigiFinder` (iOS 17.2, Swift 5, synchronized folders), camera / microphone / speech recognition / motion usage descriptions, Background Modes → Audio, and a shared scheme. Never hand-edit `project.pbxproj`.

If the local package is missing (build errors like "No such module 'DigiFinderCore'"): File → Add Package Dependencies → Add Local… → select the `DigiFinderCore` folder and link it to the `DigiFinder` target.

### 2. Secrets (optional online extras)
```
cp Secrets.example.plist DigiFinder/Resources/Secrets.plist
```
Fill in `GeminiAPIKey`, optionally `GeminiFallbackAPIKey` (used when the main key is refused), `GeminiModel` (e.g. `gemini-3.8-flash`) and `OFFContact` (an email for the Open Food Facts User-Agent). The file is gitignored. Without it the app still builds and runs fully offline; questions answer "Online help isn't set up."

### 3. Product data (§7.1, once, several GB download)
```
python3 -m venv .venv && .venv/bin/pip install duckdb huggingface_hub
.venv/bin/python tools/build_product_db.py --aisle-map tools/aisle_map.json --aisles-only --out build_out
cp build_out/products.sqlite build_out/categories.json DigiFinder/Resources/
```
Without `products.sqlite` the app falls back to `extraProducts` in `synonyms.json`; without `categories.json` it uses word search only.

### 4. YOLO model
`coremltools` needs Python 3.13 or older, so use a separate 3.9–3.12 venv:
```
python3.12 -m venv .venv-yolo && .venv-yolo/bin/pip install ultralytics
.venv-yolo/bin/yolo export model=yolov8s-oiv7.pt format=coreml nms=True
cp -R yolov8s-oiv7.mlpackage DigiFinder/Resources/
```
Without the model the app runs with no YOLO labels (LiDAR obstacles are announced as "Obstacle ahead").

### 5. Build and test
If `xcode-select -p` points at the Command Line Tools, point the tools at Xcode first:
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd DigiFinderCore && swift test)
xcodebuild -scheme DigiFinder -destination 'generic/platform=iOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/DigiFinder CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme DigiFinder -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/DigiFinder build
```
Keep `-derivedDataPath` outside an iCloud-synced Desktop or Documents folder; otherwise the Simulator codesign step fails with "resource fork, Finder information, or similar detritus not allowed".

The app builds without any of the Resources data files above (model, database, categories, secrets). In the Simulator it opens to "Camera unavailable" with a debug panel: type a request (e.g. "coffee") or send test events to drive the session. On a device, run from Xcode with your signing team; the demo phone is an iPhone 13 Pro (LiDAR).
