// ZaloMultiApp.swift
// ZaloMulti
//
// Entry point (@main) — khởi tạo app với CloneStore và window config.
// Auto-update kiểu Telegram: nhấn "Cập nhật" → tải + cài + khởi động lại.

import SwiftUI

@main
struct ZaloMultiApp: App {
    @StateObject private var cloneStore = CloneStore()
    @StateObject private var notificationMonitor = NotificationMonitor()
    @StateObject private var updater = InAppUpdater.shared
    @State private var showUpdateSheet = false
    
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
                .environmentObject(updater)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    // Migration: cleanup dữ liệu cũ
                    MigrationManager.shared.runMigrations()
                    MigrationManager.shared.cleanupOldVersionData()
                    
                    // Kiểm tra trạng thái hỗ trợ
                    DonateManager.checkAndPromptDonate()
                    
                    // Kiểm tra cập nhật ngầm (Telegram-style)
                    if SettingsManager.shared.settings.checkUpdateOnStartup {
                        updater.checkForUpdates()
                    }
                }
                .onChange(of: updater.state) { _, newState in
                    // Tự động hiện sheet khi phát hiện bản mới
                    if case .available = newState {
                        showUpdateSheet = true
                    }
                }
                .sheet(isPresented: $showUpdateSheet) {
                    UpdateProgressView(updater: updater)
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
                    updater.checkForUpdates(showUpToDatePrompt: true)
                    showUpdateSheet = true
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
                .environmentObject(updater)
        }
    }
}
