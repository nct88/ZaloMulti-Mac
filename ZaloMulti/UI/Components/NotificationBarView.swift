// NotificationBarView.swift
// ZaloMulti
//
// Thanh thông báo Zalo source status

import SwiftUI

struct NotificationBarView: View {
    @EnvironmentObject var store: CloneStore
    
    var body: some View {
        let zaloInfo = store.engine.detectSourceZalo()
        
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(zaloInfo.installed ? Color.green : Color.orange)
                    .frame(width: 28, height: 28)
                
                Image(systemName: zaloInfo.installed ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(zaloInfo.installed ? "Zalo Desktop đã sẵn sàng" : "Chưa cài Zalo Desktop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(zaloInfo.installed
                     ? "Phiên bản \(zaloInfo.version ?? "N/A") — Sẵn sàng tạo clone"
                     : "Cài Zalo từ zalo.me/pc để bắt đầu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Version badge
            if let version = zaloInfo.version {
                Text("v\(version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(zaloInfo.installed ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (zaloInfo.installed ? Color.green : Color.orange)
                            .opacity(0.12)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(zaloInfo.installed
                      ? Color.green.opacity(0.08)
                      : Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            zaloInfo.installed
                            ? Color.green.opacity(0.2)
                            : Color.orange.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
