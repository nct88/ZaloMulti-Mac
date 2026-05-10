// PrivateNotification.swift
// ZaloMulti
//
// Model đại diện cho một thông báo tin nhắn riêng tư từ Zalo clone.

import Foundation

/// Một thông báo tin nhắn nội bộ — hiển thị trong sidebar thay vì macOS notification
struct PrivateNotification: Identifiable, Equatable {
    let id = UUID()
    let cloneId: UUID?
    let cloneName: String
    let avatarColor: String
    let title: String           // Tên người gửi
    let body: String            // Nội dung tin nhắn (cắt ngắn)
    let timestamp: Date
    var isRead: Bool = false
    
    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "vừa xong" }
        if interval < 3600 { return "\(Int(interval / 60)) phút" }
        if interval < 86400 { return "\(Int(interval / 3600)) giờ" }
        return "\(Int(interval / 86400)) ngày"
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm · dd/MM"
        return formatter.string(from: timestamp)
    }
}
