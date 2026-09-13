import SwiftUI
import ProjectLocale

@main
struct PLocale: App {
    init() {
        do {
            try L10n.configure(
                apiKey: Self.config.apiKey,
                serverURL: Self.config.serverURL,
                environment: Self.config.env,
                appVersion: Self.config.appVersion,
                logLevel: .debug  // verbose logging for testing; use .warning/.info in production
            )
        } catch {
            print("[TestApp] L10n.configure failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    // Test credentials for the Project Locale server.
    // `appVersion` is read from Info.plist (CFBundleShortVersionString).
    // Bumping the version in Xcode invalidates the SDK cache and triggers
    // a full sync for the new AppVersion on the server.
    enum config {
        static let apiKey = "Please replace this with your own API key"
        static let serverURL = URL(string: "https://p-locale.eu")!
        static let env = "dev" // available environments: dev, qa, prod
        static var appVersion: String {
            (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        }
    }
}
