# Project Locale — iOS SDK

Project Locale is an over-the-air localization platform for iOS apps. Update translations instantly without going through the App Store review process.

This repository contains the **ProjectLocale SDK** (as a prebuilt static XCFramework) and a sample app that demonstrates how to integrate it.

For more information, visit [p-locale.eu](https://p-locale.eu).

## Features

- Over-the-air translation delivery with delta sync
- Real-time updates via WebSocket — translation changes are pushed instantly
- Offline-first — bundled fallback ensures the app always works
- Incremental updates — only changed keys are downloaded after the initial sync
- Works with SwiftUI (`L10nText`) and imperative code (`L10n.string`)
- Combine-based `L10n.observer` for reactive UI updates
- Per-environment and per-version translation management (dev / qa / prod)
- Revision tracking with automatic cache invalidation

## Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Manual (XCFramework)

1. Download or clone this repository.
2. Drag `ProjectLocale.xcframework` into your Xcode project.
3. In your target's **General** tab, make sure the framework appears under **Frameworks, Libraries, and Embedded Content** with "Do Not Embed" (it is a static library).

## Getting Your API Key

1. Sign up at [p-locale.eu](https://p-locale.eu) and create your account.
2. Create a new project in the dashboard.
3. Navigate to your project settings — your API key (`pl_...`) is displayed there.
4. Each project has a unique API key. The SDK uses it to identify which project to sync translations for.

## Quick Start

### 1. Configure the SDK

Call `L10n.configure` once at app startup, typically in your `App.init()`:

```swift
import ProjectLocale

@main
struct MyApp: App {
    init() {
        do {
            try L10n.configure(
                apiKey: "pl_your_api_key_here",
                serverURL: URL(string: "https://p-locale.eu")!,
                environment: "prod",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
        } catch {
            print("L10n configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 2. Sync translations

Fetch project metadata and download all translation bundles:

```swift
let info = try await L10n.projectInfo()
let syncedLocales = try await L10n.syncAll()
```

### 3. Use translations

**SwiftUI:**

```swift
L10nText("common/welcome_title", default: "Welcome")
```

**Imperative:**

```swift
let title = L10n.string("common/welcome_title", default: "Welcome")
```

### 4. Switch language

```swift
L10n.setLanguage("uk")
```

The SDK exposes `L10n.observer` (an `ObservableObject`) — observe it with `@ObservedObject` to automatically re-render views when translations change.

## Configuration Options

| Parameter | Default | Description |
|---|---|---|
| `apiKey` | — | Your project API key (required) |
| `serverURL` | — | Server URL (required) |
| `environment` | `"prod"` | Target environment: `dev`, `qa`, or `prod` |
| `appVersion` | `nil` | App version string for per-version translations |
| `logLevel` | `.warning` | Logging verbosity: `.debug`, `.info`, `.warning`, `.error`, `.off` |
| `realtimeEnabled` | `false` | Enable WebSocket for real-time translation updates |

## How Sync Works

1. **First launch** — the SDK downloads the full translation set for all configured languages.
2. **Subsequent launches** — the SDK sends its current revision number. If nothing changed, the server responds with `304 Not Modified` (zero traffic). If translations were updated, only the changed keys are sent (delta sync).
3. **Offline** — the SDK uses cached translations from the previous session. If no cache exists, it falls back to the default values provided in code.
4. **App version change** — bumping the version in Xcode invalidates the cache and triggers a full sync for the new version.

## Real-Time Updates

The SDK supports real-time translation delivery via WebSocket. When enabled, translation changes made on the server are pushed to the app instantly — no need to restart or re-sync.

### Enable WebSocket

Pass `realtimeEnabled: true` when configuring the SDK:

```swift
try L10n.configure(
    apiKey: "pl_your_api_key_here",
    serverURL: URL(string: "https://p-locale.eu")!,
    environment: "prod",
    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
    realtimeEnabled: true
)
```

### Reactive UI with Combine

The SDK exposes `L10n.observer`, a `TranslationObserver` conforming to `ObservableObject`. Its `revision` property increments on every translation change. Use `@ObservedObject` to drive SwiftUI re-renders:

```swift
struct TranslatedView: View {
    @ObservedObject private var observer = L10n.observer

    var body: some View {
        let _ = observer.revision
        Text(L10n.string("common/greeting", default: "Hello"))
    }
}
```

Or use the built-in `L10nText` wrapper, which handles observation automatically:

```swift
L10nText("common/greeting", default: "Hello")
```

### How It Works with Delta Sync

WebSocket and delta sync are complementary:

- **WebSocket** pushes individual key changes in real time while the app is running.
- **Delta sync** runs on app startup and downloads all changes that occurred since the last session.

Both mechanisms update the same in-memory cache and trigger the same `L10n.observer` notification, so your UI code doesn't need to distinguish between them.

## Sample App

The `Sources/` directory contains a sample app that demonstrates SDK integration. To run it:

1. Open `TestApp.xcodeproj` in Xcode.
2. Replace the API key in `PLocale.swift` with your own.
3. Build and run on a simulator or device.

## License

Copyright 2026 Oleksandr Chornyi. All rights reserved. See [LICENSE](LICENSE) for details.
