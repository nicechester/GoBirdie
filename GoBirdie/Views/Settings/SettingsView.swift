//
//  SettingsView.swift
//  GoBirdie

import SwiftUI
import StoreKit
import GoBirdieCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var localization = LocalizationManager.shared

    private var isPatron: Bool {
        UserDefaults.standard.bool(forKey: "isPatron")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("settings.courses".localized) {
                    NavigationLink {
                        CourseManagerView()
                    } label: {
                        Label("settings.manageCourses".localized, systemImage: "map")
                    }
                }

                Section("settings.equipment".localized) {
                    NavigationLink {
                        MyClubsView()
                    } label: {
                        Label("settings.myClubs".localized, systemImage: "figure.golf")
                    }
                }

                InsightsSection()
                LanguageSection()
                SyncServerSection()
                TeeSection()
                if !isPatron {
                    TipJarSection()
                }
                AboutSection()
            }
            .navigationTitle("settings.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPatron {
                    ToolbarItem(placement: .principal) {
                        HStack {
                            Text("settings.title".localized)
                            Image("patron-badge")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)
                        }
                    }
                }
            }
        }
        .id(localization.currentLanguage) // Force refresh on language change
    }
}

// MARK: - Language Section

private struct LanguageSection: View {
    @ObservedObject var localization = LocalizationManager.shared

    var body: some View {
        Section {
            Picker("settings.language".localized, selection: $localization.currentLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
        } header: {
            Text("settings.language".localized)
        } footer: {
            Text("settings.languageFooter".localized)
                .font(.caption)
        }
    }
}

// MARK: - Insights Section

private struct InsightsSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Section {
            Picker("settings.sgBaseline".localized, selection: $appState.sgBaseline) {
                ForEach(SGBaseline.allCases, id: \.self) { baseline in
                    Text(baseline.localizedName).tag(baseline)
                }
            }
        } header: {
            Text("settings.insights".localized)
        } footer: {
            Text("settings.sgBaselineFooter".localized)
                .font(.caption)
        }
    }
}

// MARK: - Sync Server Section

private struct SyncServerSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Section {
            Toggle(isOn: $appState.syncServerEnabled) {
                Label("settings.desktopSync".localized, systemImage: "antenna.radiowaves.left.and.right")
            }
            if appState.syncServerEnabled {
                LabeledContent("settings.status".localized, value: appState.syncServerRunning ? "settings.discoverable".localized : "settings.starting".localized)
                    .foregroundStyle(appState.syncServerRunning ? .green : .secondary)
            }
        } header: {
            Text("settings.sync".localized)
        } footer: {
            Text("settings.syncFooter".localized)
                .font(.caption)
        }
    }
}

// MARK: - Tee Section

private struct TeeSection: View {
    @EnvironmentObject var appState: AppState

    private let teeColors = ["Black", "Blue", "White", "Yellow", "Red"]
    private let teeColorValues: [String: Color] = [
        "Black": .primary, "Blue": .blue, "White": .gray,
        "Yellow": .yellow, "Red": .red
    ]
    
    private func localizedTeeColor(_ color: String) -> String {
        switch color {
        case "Black": return "tee.black".localized
        case "Blue": return "tee.blue".localized
        case "White": return "tee.white".localized
        case "Yellow": return "tee.yellow".localized
        case "Red": return "tee.red".localized
        default: return color
        }
    }

    var body: some View {
        Section("settings.tee".localized) {
            Picker("settings.teeColor".localized, selection: $appState.teeColor) {
                ForEach(teeColors, id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(teeColorValues[color] ?? .gray)
                            .frame(width: 12, height: 12)
                        Text(localizedTeeColor(color))
                    }
                    .tag(color)
                }
            }
        }
    }
}

// MARK: - Tip Jar Section

private struct TipJarSection: View {
    @State private var products: [Product] = []
    @State private var isPurchasing = false
    @State private var thankYouMessage: String?
    @State private var loadFailed = false

    private let productIDs = [
        "io.github.nicechester.GoBirdie.tip.sleeve",
        "io.github.nicechester.GoBirdie.tip.snack",
        "io.github.nicechester.GoBirdie.tip.drink"
    ]

    var body: some View {
        Section {
            if let msg = thankYouMessage {
                HStack {
                    Spacer()
                    Text(msg)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if loadFailed {
                Text("settings.loadProductsFailed".localized)
                    .font(.caption).foregroundStyle(.secondary)
            } else if products.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ForEach(products) { product in
                    Button {
                        Task { await buy(product) }
                    } label: {
                        HStack {
                            Text(localName(for: product))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(product.displayPrice)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isPurchasing)
                }
            }
        } header: {
            Text("settings.supportDevelopment".localized)
        } footer: {
            Text("settings.tipJarFooter".localized)
                .font(.caption)
        }
        .task {
            do {
                let fetched = try await Product.products(for: productIDs)
                if fetched.isEmpty {
                    loadFailed = true
                } else {
                    products = fetched.sorted { $0.price < $1.price }
                }
            } catch {
                print("[TipJar] Failed to fetch products: \(error)")
                loadFailed = true
            }
        }
    }

    private func buy(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success:
                UserDefaults.standard.set(true, forKey: "isPatron")
                thankYouMessage = "settings.thankYou".localized
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("[TipJar] Purchase failed: \(error)")
        }
    }

    private func localName(for product: Product) -> String {
        switch product.id {
        case "io.github.nicechester.GoBirdie.tip.sleeve": return "tip.sleeve".localized
        case "io.github.nicechester.GoBirdie.tip.snack":  return "tip.snack".localized
        case "io.github.nicechester.GoBirdie.tip.drink":  return "tip.drink".localized
        default: return product.displayName
        }
    }
}

// MARK: - About Section

private struct AboutSection: View {
    var body: some View {
        Section("settings.about".localized) {
            LabeledContent("settings.version".localized, value: appVersion)
            Link("settings.manual".localized, destination: URL(string: "https://github.com/nicechester/GoBirdie/blob/main/MANUAL.md")!)
            LabeledContent("settings.mapData".localized, value: "© OpenStreetMap contributors")
            LabeledContent("settings.maps".localized, value: "© MapLibre")
            LabeledContent("settings.license".localized, value: "© 2026 Chester Kim. All rights reserved.")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - SGBaseline Localization Extension

extension SGBaseline {
    var localizedName: String {
        switch self {
        case .scratch: return "baseline.scratch".localized
        case .single: return "baseline.single".localized
        case .bogey: return "baseline.bogey".localized
        case .highCap: return "baseline.highCap".localized
        }
    }
}
