# Tokn

<img src="Tokn/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Tokn icon" />

A macOS menu bar app that shows your Claude.ai session usage at a glance — built from scratch so you know exactly what it does with your session key.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## What it shows

- **Session (5h)** — usage within the current 5-hour rolling window, with time until reset
- **Weekly (7d)** — usage across the current 7-day window
- Color-coded status: green → orange (≥50%) → red (≥80%)

## Installation

1. Download `Tokn-1.0.3.dmg` from the [latest release](../../releases/latest)
2. Open the DMG and drag **Tokn** into **Applications**
3. On first launch, right-click → **Open** once (macOS Gatekeeper prompt for unsigned apps — one-time only)

## Setup

1. Open [claude.ai](https://claude.ai) in your browser
2. Open DevTools (⌘⌥I in Chrome/Safari)
3. Go to **Application → Cookies → `claude.ai`**
4. Copy the value of the `sessionKey` cookie (starts with `sk-ant-`)
5. Click the Tokn icon in your menu bar and paste it in

Your session key is stored only in the macOS Keychain — never written to disk or sent anywhere other than `claude.ai`.

## Building from source

Requires Xcode 16+ and macOS 14+.

```bash
git clone https://github.com/iPwnds/Tokn.git
cd Tokn
open Tokn.xcodeproj
```

Hit **Run** (⌘R) in Xcode. No dependencies, no package manager.

Or from the command line:

```bash
xcodebuild -project Tokn.xcodeproj -scheme Tokn -configuration Release build CODE_SIGN_IDENTITY="-"
```

## Architecture

| Layer | Files |
|---|---|
| Entry point | `Tokn/ToknApp.swift` |
| App state | `Tokn/App/AppModel.swift` |
| Models | `Tokn/Models/` |
| Keychain + Settings | `Tokn/Repositories/` |
| Network + Usage | `Tokn/Services/` |
| UI | `Tokn/Views/` |

The app hits two Claude API endpoints — `GET /api/organizations` (to resolve your org ID) and `GET /api/organizations/{id}/usage` (for the usage data). All source is plain Swift with no third-party dependencies, so the full behaviour is auditable in a few hundred lines.

## License

MIT — see [LICENSE](LICENSE).
