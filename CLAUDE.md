# Commands

- Build app bundle: `./build.sh` (outputs the `.app` in the repo root)
- Run self-check: `./test.sh` (compiles `Core.swift` + `tests/main.swift`; samples go to `.build/`)
- Format: `swift format -i -r .` (config in `.swift-format`)

# Layout

- `Core.swift`: logic with no UI, covered by `tests/main.swift`
- `main.swift`: AppKit UI, built without Xcode via `swiftc`

# UI text

Write UI text and README in ASD-STE100 Simplified Technical English. Do not use dashes.
