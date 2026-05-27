// NotificationMonitor.swift
// ZaloMulti
//
// Theo dõi và chặn thông báo từ các Zalo clone processes.
// Chuyển thông báo vào sidebar để bảo vệ quyền riêng tư.

@preconcurrency import Foundation
import AppKit
import SwiftUI

/// Monitor theo dõi macOS notifications từ Zalo clones
@MainActor
final class NotificationMonitor: ObservableObject {
    @Published var notifications: [PrivateNotification] = []
    @Published var unreadCount: Int = 0
    
    private var pollingTimer: Timer?
    private var lastPollTimestamp: TimeInterval = 0
    
    // Giới hạn số thông báo giữ lại
    private let maxNotifications = 100
    
    init() {
        DiagnosticLogger.info("NOTIF", "NotificationMonitor khởi tạo")
        lastPollTimestamp = Date().timeIntervalSinceReferenceDate
        startMonitoring()
    }
    
    // MARK: - Public API
    
    /// Đánh dấu một thông báo đã đọc
    func markAsRead(_ notification: PrivateNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
            updateUnreadCount()
        }
    }
    
    /// Đánh dấu tất cả đã đọc
    func markAllAsRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        updateUnreadCount()
    }
    
    /// Xóa một thông báo
    func removeNotification(_ notification: PrivateNotification) {
        notifications.removeAll { $0.id == notification.id }
        updateUnreadCount()
    }
    
    /// Xóa tất cả thông báo
    func clearAll() {
        notifications.removeAll()
        unreadCount = 0
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        // Polling: kiểm tra Zalo notification log files
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollZaloNotifications()
            }
        }
        
        DiagnosticLogger.info("NOTIF", "Bắt đầu monitoring notifications")
    }
    
    /// Polling Zalo notification logs cho thông báo mới
    private func pollZaloNotifications() {
        let basePath = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti/Data"
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: basePath) else { return }
        
        // Scan qua từng clone directory
        guard let cloneDirs = try? fm.contentsOfDirectory(atPath: basePath) else { return }
        
        for dir in cloneDirs where dir.hasPrefix("clone") {
            let cloneIndex = Int(dir.replacingOccurrences(of: "clone", with: "")) ?? 0
            
            // Kiểm tra Zalo notification database (Partitions/zalo/Notification)
            let notifPaths = [
                "\(basePath)/\(dir)/ZaloData/Partitions/zalo/Local Storage/leveldb",
                "\(basePath)/\(dir)/ZaloData/Databases"
            ]
            
            for notifPath in notifPaths {
                guard fm.fileExists(atPath: notifPath) else { continue }
                
                // Kiểm tra file modification time
                if let attrs = try? fm.attributesOfItem(atPath: notifPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    let modTime = modDate.timeIntervalSinceReferenceDate
                    
                    // Chỉ xử lý nếu có thay đổi mới
                    if modTime > lastPollTimestamp {
                        // Có activity mới từ clone này
                        let profile = AvatarExtractor.extractProfile(cloneIndex: cloneIndex)
                        let cloneName = profile?.displayName ?? "Clone \(cloneIndex)"
                        let avatarColor = CloneAccount.colorForIndex(cloneIndex)
                        
                        // Tạo thông báo activity
                        let isDuplicate = notifications.contains { n in
                            n.cloneName == cloneName &&
                            Date().timeIntervalSince(n.timestamp) < 10
                        }
                        
                        if !isDuplicate {
                            addNotification(
                                cloneId: nil,
                                cloneName: cloneName,
                                avatarColor: avatarColor,
                                title: "Hoạt động mới",
                                body: "Có tin nhắn hoặc hoạt động mới từ \(cloneName)"
                            )
                        }
                    }
                }
            }
        }
        
        lastPollTimestamp = Date().timeIntervalSinceReferenceDate
    }
    
    // MARK: - Add Notification
    
    /// Thêm thông báo từ clone cụ thể (được gọi từ CloneStore)
    func addFromClone(_ clone: CloneAccount, title: String, body: String) {
        addNotification(
            cloneId: clone.id,
            cloneName: clone.name,
            avatarColor: clone.avatarColor,
            title: title,
            body: body
        )
    }
    
    private func addNotification(
        cloneId: UUID?,
        cloneName: String,
        avatarColor: String,
        title: String,
        body: String
    ) {
        let notification = PrivateNotification(
            cloneId: cloneId,
            cloneName: cloneName,
            avatarColor: avatarColor,
            title: title,
            body: body.isEmpty ? "Tin nhắn mới" : body,
            timestamp: Date()
        )
        
        // Thêm vào đầu danh sách
        withAnimation(.easeInOut(duration: 0.2)) {
            notifications.insert(notification, at: 0)
        }
        
        // Giới hạn số lượng
        if notifications.count > maxNotifications {
            notifications = Array(notifications.prefix(maxNotifications))
        }
        
        updateUnreadCount()
        
        DiagnosticLogger.info("NOTIF", "[\(cloneName)] \(title): \(body.prefix(50))")
    }
    
    private func updateUnreadCount() {
        unreadCount = notifications.filter { !$0.isRead }.count
    }
}
