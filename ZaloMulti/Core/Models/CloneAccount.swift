// CloneAccount.swift
// ZaloMulti
//
// Model chính đại diện cho một Zalo clone instance.

import Foundation

/// Trạng thái của một clone
enum CloneStatus: String, Codable, CaseIterable {
    case running  = "running"
    case stopped  = "stopped"
    case paused   = "paused"
    case creating = "creating"
    
    var displayName: String {
        switch self {
        case .running:  return "Đang chạy"
        case .stopped:  return "Đã dừng"
        case .paused:   return "Tạm dừng"
        case .creating: return "Đang tạo..."
        }
    }
    
    var iconName: String {
        switch self {
        case .running:  return "play.circle.fill"
        case .stopped:  return "stop.circle.fill"
        case .paused:   return "pause.circle.fill"
        case .creating: return "gear.circle.fill"
        }
    }
}

/// Model chính cho một tài khoản Zalo clone
struct CloneAccount: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    
    // Thông tin cơ bản
    var name: String                    // "Truong Business"
    var phoneNumber: String = ""        // "0901234567"
    
    // Clone-specific
    var cloneIndex: Int                 // 1, 2, 3...
    var bundleID: String                // "com.vng.zalo.clone1"
    var appPath: String                 // path to clone app
    var dataPath: String                // path to clone data
    
    // Trạng thái
    var status: CloneStatus = .stopped
    var processID: Int32?               // PID khi đang chạy
    
    // Giao diện
    var avatarColor: String             // Hex color cho avatar
    
    // Thời gian
    var createdAt: Date = Date()
    var lastOpenedAt: Date?
    
    // Device info
    var deviceId: String?
    var deviceName: String?
    
    static func == (lhs: CloneAccount, rhs: CloneAccount) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.processID == rhs.processID &&
        lhs.name == rhs.name &&
        lhs.phoneNumber == rhs.phoneNumber
    }
}

// MARK: - Avatar Colors
extension CloneAccount {
    static let avatarColors: [String] = [
        "#007AFF", "#30D158", "#FF6B35", "#BF5AF2", "#FF3B30",
        "#5AC8FA", "#FF9500", "#AC8E68", "#64D2FF", "#FF2D55",
    ]
    
    static func colorForIndex(_ index: Int) -> String {
        avatarColors[index % avatarColors.count]
    }
}
