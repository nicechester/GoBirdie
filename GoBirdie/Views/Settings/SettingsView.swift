//
//  SettingsView.swift
//  GoBirdie

import SwiftUI
import StoreKit
import GoBirdieCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        NavigationStack {
            List {
                Section("Courses") {
                    NavigationLink {
                        CourseManagerView()
                    } label: {
                        Label("Manage Courses", systemImage: "map")
                    }
                }

                TeeSection()
                TipJarSection()
                AboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        Section("Tee") {
            Picker("Tee Color", selection: $appState.teeColor) {
                ForEach(teeColors, id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(teeColorValues[color] ?? .gray)
                            .frame(width: 12, height: 12)
                        Text(color)
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
                Text("Could not load products. Make sure the StoreKit config is set in the scheme.")
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
                            Text(product.displayName)
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
            Text("Support Development")
        } footer: {
            Text("GoBirdie is free with no ads. Tips help cover the $99/year Apple Developer fee.")
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
                thankYouMessage = "Thank you! ⛳️ You're awesome."
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
}

// MARK: - About Section

private struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Link("GitHub", destination: URL(string: "https://github.com/nicechester/GoBirdie")!)
            LabeledContent("Map Data", value: "© OpenStreetMap contributors")
            LabeledContent("Maps", value: "© MapLibre")
            LabeledContent("License", value: "MIT")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
