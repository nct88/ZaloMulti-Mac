// ZaloMultiApp.swift
// ZaloMulti
//
// Entry point (@main) — khởi tạo app với CloneStore và window config.
// Auto-update kiểu Telegram: nhấn "Cập nhật" → tải + cài + khởi động lại.

import SwiftUI

@main
struct ZaloMultiApp: App {
    @ObservedObject private var updater = InAppUpdater.shared
    
    init() {
        // Security initialization
        AntiTamper.initialize()
        
        // Logger init
        DiagnosticLogger.info("APP", "ZaloMulti — khởi động")
        DiagnosticLogger.info("APP", "Log file: \(DiagnosticLogger.logFilePath)")
        
        // Pre-init singletons
        _ = CloneStore.shared
        _ = NotificationMonitor.shared
        
        let zaloInfo = ZaloCloneEngine().detectSourceZalo()
        DiagnosticLogger.info("APP", "Zalo Desktop: installed=\(zaloInfo.installed), version=\(zaloInfo.version ?? "N/A")")
    }
    var body: some Scene {
        WindowGroup("Zalỏ - macOS") {
            ContentView()
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    // Migration: cleanup dữ liệu cũ
                    MigrationManager.shared.runMigrations()
                    MigrationManager.shared.cleanupOldVersionData()
                    
                    // Kiểm tra trạng thái hỗ trợ (delay để SwiftUI window sẵn sàng)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        DonateManager.checkAndPromptDonate()
                    }
                    
                    // Kiểm tra cập nhật ngầm (delay)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if SettingsManager.shared.settings.checkUpdateOnStartup {
                            DiagnosticLogger.info("APP", "Bắt đầu kiểm tra cập nhật...")
                            InAppUpdater.shared.checkForUpdates()
                        }
                    }
                }
                .sheet(isPresented: $updater.showUpdateSheet) {
                    UpdateProgressView(updater: InAppUpdater.shared)
                        .frame(minWidth: 420, minHeight: 300)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Thêm Clone Mới") {
                    CloneStore.shared.showAddCloneSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Kiểm tra cập nhật...") {
                    InAppUpdater.shared.checkForUpdates(showUpToDatePrompt: true)
                    InAppUpdater.shared.showUpdateSheet = true
                }
            }
            CommandMenu("Clone") {
                Button("Dừng tất cả") {
                    CloneStore.shared.stopAllClones()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}
