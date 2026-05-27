// ContentView.swift
// ZaloMulti
//
// Layout tổng thể: Main Content (trái) + Sidebar (phải)

import SwiftUI

struct ContentView: View {
    @ObservedObject var cloneStore = CloneStore.shared
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
        .alert("Lỗi", isPresented: $cloneStore.showError) {
            Button("OK") { cloneStore.showError = false }
        } message: {
            Text(cloneStore.errorMessage ?? "Đã xảy ra lỗi không xác định")
        }
    }
}
