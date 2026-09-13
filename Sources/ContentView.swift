import SwiftUI
import ProjectLocale

// MARK: - Startup phase

enum StartupPhase: Equatable {
    case syncing(step: String)
    case ready(ProjectInfo, syncedLocales: [String], expectedLocales: [String])
    case fallbackCached(availableLocales: [String])
    case fallbackEnglish(reason: String)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Root

struct ContentView: View {
    @State private var phase: StartupPhase = .syncing(step: "Starting…")
    @State private var lang: String = L10n.currentLanguage

    var body: some View {
        Group {
            switch phase {
            case let .syncing(step):
                SplashView(step: step)
            case let .ready(info, synced, expected):
                MainView(
                    phase: $phase,
                    lang: $lang,
                    info: info,
                    availableLocales: expected,
                    syncedLocales: synced,
                    modeLabel: "online, synced with server",
                    modeColor: .green,
                    reload: reload
                )
            case let .fallbackCached(locales):
                MainView(
                    phase: $phase,
                    lang: $lang,
                    info: nil,
                    availableLocales: locales,
                    syncedLocales: locales,
                    modeLabel: "offline — using cached translations from last session",
                    modeColor: .orange,
                    reload: reload
                )
            case let .fallbackEnglish(reason):
                MainView(
                    phase: $phase,
                    lang: $lang,
                    info: nil,
                    availableLocales: ["en"],
                    syncedLocales: [],
                    modeLabel: "offline, no cache — falling back to English (\(reason))",
                    modeColor: .red,
                    reload: reload
                )
            }
        }
        .task(id: 0) { await bootstrap() }
    }

    // MARK: - Startup flow

    private func bootstrap() async {
        phase = .syncing(step: "Connecting to server…")

        // 1. project info
        let info: ProjectInfo
        do {
            info = try await L10n.projectInfo()
        } catch {
            handleNetworkFailure(reason: error.localizedDescription)
            return
        }

        phase = .syncing(step: "Fetched \(info.languages.count) languages. Syncing bundles…")

        // 2. sync all bundles
        let synced: [String]
        do {
            synced = try await L10n.syncAll()
        } catch {
            handleNetworkFailure(reason: "syncAll: \(error.localizedDescription)")
            return
        }

        // Pick active language from preferred if it exists in the current
        // (env, appVersion); otherwise fall back to source language.
        let expected = info.languages(for: PLocale.config.env, appVersion: PLocale.config.appVersion) ?? info.languages
        if !expected.contains(lang) {
            lang = info.sourceLanguage
        }
        L10n.setLanguage(lang)

        phase = .ready(info, syncedLocales: synced, expectedLocales: expected)
    }

    private func handleNetworkFailure(reason: String) {
        if L10n.hasCachedTranslations {
            let locales = L10n.availableLanguages
            if !locales.contains(lang) {
                lang = locales.first ?? "en"
            }
            L10n.setLanguage(lang)
            phase = .fallbackCached(availableLocales: locales)
        } else {
            lang = "en"
            L10n.setLanguage("en")
            phase = .fallbackEnglish(reason: reason)
        }
    }

    private func reload() {
        Task { await bootstrap() }
    }
}

// MARK: - Splash

private struct SplashView: View {
    let step: String
    var body: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.3)
            Text("Project Locale").font(.title2).fontWeight(.semibold)
            Text(step)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Main

private struct MainView: View {
    @Binding var phase: StartupPhase
    @Binding var lang: String
    let info: ProjectInfo?
    let availableLocales: [String]
    let syncedLocales: [String]
    let modeLabel: String
    let modeColor: Color
    let reload: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(modeLabel)
                        .font(.footnote)
                        .foregroundStyle(modeColor)
                }

                if let info {
                    Section("Project") {
                        LabeledContent("Name", value: info.name)
                        LabeledContent("Source", value: info.sourceLanguage)
                        LabeledContent("Languages", value: availableLocales.joined(separator: ", "))
                        LabeledContent("Environments", value: info.environments.joined(separator: ", "))
                    }
                }

                Section("Sync") {
                    LabeledContent("Current language", value: lang)
                    let snap = L10n.revisionSnapshot()
                    if let entry = snap[lang] {
                        LabeledContent("App version", value: entry.appVersion.isEmpty ? "—" : entry.appVersion)
                        LabeledContent("Revision", value: "\(entry.revision)")
                    } else {
                        LabeledContent("App version", value: "—")
                        LabeledContent("Revision", value: "—")
                    }
                }

                Section("Language") {
                    Picker("Active", selection: $lang) {
                        ForEach(availableLocales, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: lang) { _, newValue in
                        L10n.setLanguage(newValue)
                    }
                }

                let keys = CacheReader.keys(for: lang)
                Section("Translations (\(keys.count))") {
                    if keys.isEmpty {
                        Text("No translations loaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keys, id: \.key) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.key)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(L10n.string(entry.key, default: entry.value))
                                    .font(.body)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Actions") {
                    Button {
                        reload()
                    } label: {
                        Text("Re-sync from server")
                    }
                }
            }
            .navigationTitle("Project Locale")
        }
    }
}

private enum CacheReader {
    struct CachedBundle: Codable {
        let translations: [String: String]
    }

    static func keys(for locale: String) -> [(key: String, value: String)] {
        guard let dir = cacheDir() else { return [] }
        let file = dir.appendingPathComponent("\(locale).json")
        guard let data = try? Data(contentsOf: file),
              let bundle = try? JSONDecoder().decode(CachedBundle.self, from: data)
        else { return [] }
        return bundle.translations
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    private static func cacheDir() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return nil }
        let scope = String(PLocale.config.apiKey.suffix(12))
        let env = PLocale.config.env
        return base.appendingPathComponent("ProjectLocale/\(scope)/\(env)")
    }
}

#Preview {
    ContentView()
}
