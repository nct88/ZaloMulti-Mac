// ZaloMultiApp.swift
// ZaloMulti
//
// Entry point (@main) — khởi tạo app với CloneStore và window config.

import SwiftUI

@main
struct ZaloMultiApp: App {
    @StateObject private var cloneStore = CloneStore()
    @StateObject private var notificationMonitor = NotificationMonitor()
    
    init() {
        // Security initialization
        AntiTamper.initialize()
        
        // Logger init
        DiagnosticLogger.info("APP", "ZaloMulti — khởi động")
        DiagnosticLogger.info("APP", "Log file: \(DiagnosticLogger.logFilePath)")
        
        let zaloInfo = ZaloCloneEngine().detectSourceZalo()
        DiagnosticLogger.info("APP", "Zalo Desktop: installed=\(zaloInfo.installed), version=\(zaloInfo.version ?? "N/A")")
    }
    var body: some Scene {
        WindowGroup("Zalỏ - macOS") {
            ContentView()
                .environmentObject(cloneStore)
                .environmentObject(notificationMonitor)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    // Migration: cleanup dữ liệu cũ
                    MigrationManager.shared.runMigrations()
                    MigrationManager.shared.cleanupOldVersionData()
                    
                    // Kiểm tra trạng thái hỗ trợ
                    DonateManager.checkAndPromptDonate()
                    
                    // Kiểm tra cập nhật ngầm
                    UpdateManager.checkForUpdates()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Thêm Clone Mới") {
                    cloneStore.showAddCloneSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Kiểm tra cập nhật...") {
                    UpdateManager.checkForUpdates(showUpToDatePrompt: true)
                }
            }
            CommandMenu("Clone") {
                Button("Dừng tất cả") {
                    cloneStore.stopAllClones()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(cloneStore)
                .environmentObject(notificationMonitor)
        }
    }
}

// MARK: - Auto Update Manager (GitHub Releases)
@MainActor
final class UpdateManager {
    // Repository config (encrypted via SecureConfig)
    private static var apiURL: String { SecureConfig.githubAPIURL }
    
    /// Kiểm tra phiên bản mới trên GitHub
    static func checkForUpdates(showUpToDatePrompt: Bool = false) {
        Task {
            guard let url = URL(string: apiURL) else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    if showUpToDatePrompt {
                        DiagnosticLogger.warning("UPDATE", "Lỗi gọi API: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                        showErrorAlert()
                    }
                    return
                }
                
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Lấy phiên bản hiện tại từ Info.plist
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                
                DiagnosticLogger.info("UPDATE", "Current: \(currentVersion), Latest: \(latestVersion)")
                
                if isNewerVersion(latest: latestVersion, current: currentVersion) {
                    showUpdateAlert(latestVersion: latestVersion, releaseNotes: release.body, releaseUrl: release.htmlUrl)
                } else if showUpToDatePrompt {
                    showUpToDateAlert()
                }
                
            } catch {
                DiagnosticLogger.error("UPDATE", "Lỗi check update", error: error)
                if showUpToDatePrompt {
                    showErrorAlert()
                }
            }
        }
    }
    
    private static func isNewerVersion(latest: String, current: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }
    
    private static func showUpdateAlert(latestVersion: String, releaseNotes: String?, releaseUrl: String) {
        let alert = NSAlert()
        alert.messageText = "Có bản cập nhật mới!"
        alert.informativeText = "Phiên bản \(latestVersion) đã sẵn sàng để tải xuống."
        
        if let notes = releaseNotes, !notes.isEmpty {
            alert.informativeText += "\n\nNội dung cập nhật:\n\(notes.prefix(300))\(notes.count > 300 ? "..." : "")"
        }
        
        alert.addButton(withTitle: "Tải Ngay")
        alert.addButton(withTitle: "Bỏ qua")
        
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: releaseUrl) { NSWorkspace.shared.open(url) }
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: releaseUrl) { NSWorkspace.shared.open(url) }
            }
        }
    }
    
    private static func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "Bạn đang dùng bản mới nhất"
        alert.informativeText = "Zalo Multi macOS đã được cập nhật bản mới nhất."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private static func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Không thể kiểm tra cập nhật"
        alert.informativeText = "Vui lòng kiểm tra lại kết nối mạng hoặc thử lại sau."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// JSON Model mapping
private struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}
