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
        // Trigger logger initialization — writes session header
        DiagnosticLogger.info("APP", "ZaloMulti v1.0.0 — khởi động")
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
                    // Kiểm tra donate khi app mở — mở trang nếu chưa donate
                    DonateManager.checkAndPromptDonate()
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
