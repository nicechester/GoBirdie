//
//  LocalizationManager.swift
//  GoBirdie
//

import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case korean = "ko"
    
    var displayName: String {
        switch self {
        case .system: return String(localized: "language.system")
        case .english: return String(localized: "language.en")
        case .korean: return String(localized: "language.ko")
        }
    }
    
    var locale: Locale {
        switch self {
        case .system: return .current
        case .english: return Locale(identifier: "en")
        case .korean: return Locale(identifier: "ko")
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            updateBundle()
        }
    }
    
    private(set) var bundle: Bundle = .main
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        currentLanguage = AppLanguage(rawValue: saved) ?? .system
        updateBundle()
    }
    
    var effectiveLanguageCode: String {
        switch currentLanguage {
        case .system:
            return Locale.current.language.languageCode?.identifier ?? "en"
        case .english:
            return "en"
        case .korean:
            return "ko"
        }
    }
    
    var isKorean: Bool {
        effectiveLanguageCode == "ko"
    }
    
    private func updateBundle() {
        let langCode: String
        switch currentLanguage {
        case .system:
            langCode = Locale.current.language.languageCode?.identifier ?? "en"
        case .english:
            langCode = "en"
        case .korean:
            langCode = "ko"
        }
        
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.bundle = bundle
        } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
                  let bundle = Bundle(path: path) {
            self.bundle = bundle
        } else {
            self.bundle = .main
        }
    }
    
    func localizedString(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - String Extension for Localization

extension String {
    var localized: String {
        LocalizationManager.shared.localizedString(self)
    }
    
    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, arguments: arguments)
    }
}
