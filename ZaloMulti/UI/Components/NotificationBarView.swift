// NotificationBarView.swift
// ZaloMulti
//
// Thanh thông báo Zalo source status
// ⚡ Performance: Cache kết quả detectSourceZalo() thay vì gọi mỗi lần render

import SwiftUI

struct NotificationBarView: View {
    @EnvironmentObject var store: CloneStore
    @State private var zaloInstalled = false
    @State private var zaloVersion: String?
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(zaloInstalled ? Color.green : Color.orange)
                    .frame(width: 28, height: 28)
                
                Image(systemName: zaloInstalled ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(zaloInstalled ? "Zalo Desktop đã sẵn sàng" : "Chưa cài Zalo Desktop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(zaloInstalled
                     ? "Phiên bản \(zaloVersion ?? "N/A") — Sẵn sàng tạo clone"
                     : "Cài Zalo từ zalo.me/pc để bắt đầu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Version badge
            if let version = zaloVersion {
                Text("v\(version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(zaloInstalled ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (zaloInstalled ? Color.green : Color.orange)
                            .opacity(0.12)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(zaloInstalled
                      ? Color.green.opacity(0.08)
                      : Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            zaloInstalled
                            ? Color.green.opacity(0.2)
                            : Color.orange.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .onAppear {
            // Cache kết quả — chỉ detect 1 lần, không gọi trong body
            let info = store.engine.detectSourceZalo()
            zaloInstalled = info.installed
            zaloVersion = info.version
        }
    }
}
