// DashboardView.swift
// ZaloMulti
//
// Grid 2 cột hiển thị các clone cards

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: CloneStore
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            // Section header
            HStack {
                Text("TÀI KHOẢN CLONE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(store.totalCount) tài khoản")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.clones) { clone in
                    CloneCardView(clone: clone)
                }
                
                // Nút thêm clone mới
                AddCloneCardView()
                    .onTapGesture {
                        store.showAddCloneSheet = true
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .animation(.spring(response: 0.3), value: store.clones.count)
        }
        .sheet(isPresented: $store.showAddCloneSheet) {
            AddCloneView()
                .environmentObject(store)
        }
    }
}

// MARK: - Add Clone Card
struct AddCloneCardView: View {
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isHovered ? .white : .secondary)
            }
            
            Text("Thêm tài khoản")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 130)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                )
        )
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 4, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .cursor(.pointingHand)
    }
}

// MARK: - NSCursor extension
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
