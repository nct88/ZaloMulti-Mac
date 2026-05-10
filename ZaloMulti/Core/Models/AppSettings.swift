// AppSettings.swift
// ZaloMulti
//
// Cấu hình ứng dụng

import Foundation

/// Cài đặt ứng dụng lưu trong UserDefaults
struct AppSettings: Codable {
    var theme: String = "system"       // "light", "dark", "system"
    var accentColor: String = "#0068FF"
    var profileRoot: String?           // Đường dẫn custom cho data
    var maxClones: Int = 10            // Giới hạn số clone
    var autoLaunchOnStartup: Bool = false
    var showMenuBarIcon: Bool = true
    var checkUpdateOnStartup: Bool = true
}

/// Quản lý settings dùng UserDefaults
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var settings: AppSettings {
        didSet { save() }
    }
    
    private let key = "app_settings_v1"
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func reset() {
        settings = AppSettings()
    }
}
