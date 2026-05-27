// ContentView.swift
// ZaloMulti
//
// Layout tổng thể: Main Content (trái) + Sidebar (phải)

import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var cloneStore = CloneStore.shared
    @ObservedObject var updater = InAppUpdater.shared
    @State private var showSidebar = true
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Main Dashboard
            VStack(spacing: 0) {
                // Notification Bar — Zalo source status
                NotificationBarView()
                
                // Clone Grid
                DashboardView()
            }
            .frame(maxWidth: .infinity)
            
            if showSidebar {
                // Divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                
                // RIGHT: Sidebar
                SidebarView()
                    .frame(width: 240)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Ẩn/Hiện thanh bên")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(cloneStore.$showAddCloneSheet) { show in
            if show {
                DiagnosticLogger.info("UI", "Mở sheet Thêm Clone")
                cloneStore.showAddCloneSheet = false
                SheetPresenter.presentAddClone(store: cloneStore)
            }
        }
        .onReceive(updater.$showUpdateSheet) { show in
            if show {
                DiagnosticLogger.info("UI", "Mở sheet Cập nhật")
                updater.showUpdateSheet = false
                SheetPresenter.presentUpdateProgress(updater: updater)
            }
        }
        .alert("Lỗi", isPresented: $cloneStore.showError) {
            Button("OK") { cloneStore.showError = false }
        } message: {
            Text(cloneStore.errorMessage ?? "Đã xảy ra lỗi không xác định")
        }
    }
}

// MARK: - Sheet Presenter (NSWindow-based)
/// Trình chiếu sheet qua NSWindow — tránh hoàn toàn bug SwiftUI .sheet trên macOS
@MainActor
enum SheetPresenter {
    
    static func presentAddClone(store: CloneStore) {
        let view = AddCloneView()
            .environmentObject(store)
        
        presentWindow(
            content: view,
            title: "Thêm tài khoản Clone",
            size: NSSize(width: 460, height: 340)
        )
    }
    
    static func presentUpdateProgress(updater: InAppUpdater) {
        let view = UpdateProgressView(updater: updater)
        
        presentWindow(
            content: view,
            title: "Cập nhật",
            size: NSSize(width: 420, height: 300)
        )
    }
    
    private static func presentWindow<Content: View>(content: Content, title: String, size: NSSize) {
        guard let mainWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            DiagnosticLogger.error("UI", "Không tìm thấy main window")
            return
        }
        
        let hostingController = NSHostingController(rootView: content)
        let panel = NSPanel(contentViewController: hostingController)
        panel.title = title
        panel.setContentSize(size)
        panel.styleMask = [.titled, .closable, .resizable]
        panel.isMovableByWindowBackground = true
        
        mainWindow.beginSheet(panel) { _ in
            // Sheet dismissed
        }
    }
}
