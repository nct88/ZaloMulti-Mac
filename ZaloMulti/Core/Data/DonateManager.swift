// DonateManager.swift
// ZaloMulti
//
// Quản lý kiểm tra donate dựa trên HWID.
// Cơ chế: lấy Hardware UUID macOS → check Cloudflare Workers API → cache local.
// Tương thích với hệ thống donate từ ZaloMulti-Win, Messenger-Win, portfolio.

import Foundation
import AppKit
import IOKit

/// Quản lý trạng thái donate — kiểm tra HWID qua Cloudflare Workers
@MainActor
final class DonateManager {
    
    // Obfuscated config — chống sửa đổi bởi bên thứ ba
    private static let _k: [UInt8] = [0x5A, 0x61, 0x6C, 0x6F] // key
    
    // Encoded endpoints (XOR + Base64)
    private static let _ep1 = "MhUYHylbQ0A+DgIOLgRBDioIQhsoFAMBPUwFG3QWAx0xBB4cdAUJGQ=="
    private static let _ep2 = "MhUYHylbQ0A+TxgdLw4CCHQIGEA+DgIOLgQ="
    
    private static var apiBaseURL: String { _d(_ep1) }
    private static var donatePageURL: String { _d(_ep2) }
    
    // Cache file path
    private static var cacheFilePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ZaloMulti")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("donate_status.json").path
    }
    
    // MARK: - Decode helper
    
    /// Giải mã XOR + Base64
    private static func _d(_ encoded: String) -> String {
        guard let data = Data(base64Encoded: encoded) else { return "" }
        let key = _k
        var result = [UInt8]()
        for (i, byte) in data.enumerated() {
            result.append(byte ^ key[i % key.length])
        }
        return String(bytes: result, encoding: .utf8) ?? ""
    }
    
    /// Mã hóa string (dùng để generate encoded values — chỉ dùng khi dev)
    #if DEBUG
    static func _encode(_ input: String) -> String {
        let key = _k
        let inputBytes = Array(input.utf8)
        var result = [UInt8]()
        for (i, byte) in inputBytes.enumerated() {
            result.append(byte ^ key[i % key.length])
        }
        return Data(result).base64EncodedString()
    }
    #endif
    
    // MARK: - Integrity check
    
    /// Kiểm tra tính toàn vẹn — chống bypass donate check
    private static func _integrityCheck() -> Bool {
        // Verify class name hasn't been swizzled
        let className = String(describing: DonateManager.self)
        guard className == "DonateManager" else { return false }
        
        // Verify endpoints decode correctly
        let api = apiBaseURL
        let page = donatePageURL
        guard !api.isEmpty, !page.isEmpty else { return false }
        guard api.contains("workers.dev"), page.contains("donate") else { return false }
        
        return true
    }
    
    // MARK: - Public API
    
    /// Kiểm tra donate và mở trang nếu chưa donate — gọi khi app khởi động
    static func checkAndPromptDonate() {
        // Integrity check
        guard _integrityCheck() else {
            DiagnosticLogger.error("DONATE", "Integrity check failed")
            // Nếu bị tamper → mở donate page mặc định
            if let url = URL(string: "https://d.truong.it/donate") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        Task {
            let hwid = getHardwareUUID()
            DiagnosticLogger.info("DONATE", "HWID: \(hwid ?? "UNKNOWN")")
            
            guard let hwid = hwid, hwid != "UNKNOWN" else {
                DiagnosticLogger.warning("DONATE", "Không lấy được HWID → mở donate page")
                openDonateURL(hwid: nil)
                return
            }
            
            // Bước 1: Check cache local trước
            if checkLocalCache(hwid: hwid) {
                DiagnosticLogger.success("DONATE", "Đã donate (cache) → bỏ qua")
                return
            }
            
            // Bước 2: Gọi API kiểm tra
            let donated = await checkAPIStatus(hwid: hwid)
            
            if donated {
                saveLocalCache(hwid: hwid, donated: true)
                DiagnosticLogger.success("DONATE", "Đã donate (API) → cache và bỏ qua")
                return
            }
            
            // Bước 3: Chưa donate → mở trang
            DiagnosticLogger.info("DONATE", "Chưa donate → mở trang donate")
            openDonateURL(hwid: hwid)
        }
    }
    
    // MARK: - HWID (Hardware UUID)
    
    /// Lấy Hardware UUID của máy Mac (tương đương Win32_ComputerSystemProduct.UUID trên Windows)
    static func getHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }
        
        if let uuidCF = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return uuidCF
        }
        
        // Fallback: dùng serial number
        if let serialCF = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformSerialNumber" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return serialCF
        }
        
        return nil
    }
    
    // MARK: - Local Cache
    
    /// Kiểm tra cache local — tránh gọi API mỗi lần mở app
    private static func checkLocalCache(hwid: String) -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFilePath) else { return false }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: cacheFilePath))
            let cache = try JSONDecoder().decode(DonateCache.self, from: data)
            
            if cache.hwid == hwid && cache.donated {
                return true
            }
        } catch {
            DiagnosticLogger.error("DONATE", "Lỗi đọc cache", error: error)
        }
        
        return false
    }
    
    /// Lưu cache donate thành công
    private static func saveLocalCache(hwid: String, donated: Bool) {
        let cache = DonateCache(
            hwid: hwid,
            donated: donated,
            checked_at: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: URL(fileURLWithPath: cacheFilePath))
        } catch {
            DiagnosticLogger.error("DONATE", "Lỗi ghi cache", error: error)
        }
    }
    
    // MARK: - API Check
    
    /// Gọi Cloudflare Workers API kiểm tra trạng thái donate
    private static func checkAPIStatus(hwid: String) async -> Bool {
        let urlString = "\(apiBaseURL)/hwid/check?id=\(hwid)"
        guard let url = URL(string: urlString) else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DiagnosticLogger.warning("DONATE", "API trả về status code lỗi")
                return false
            }
            
            let apiResult = try JSONDecoder().decode(DonateAPIResponse.self, from: data)
            return apiResult.donated
        } catch {
            DiagnosticLogger.error("DONATE", "API check lỗi", error: error)
            return false
        }
    }
    
    // MARK: - Open Donate Page
    
    /// Mở trang donate trong browser mặc định
    private static func openDonateURL(hwid: String?) {
        var urlString = donatePageURL
        if let hwid = hwid {
            urlString += "?hwid=\(hwid)"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Models

/// Cache local cho trạng thái donate
private struct DonateCache: Codable {
    let hwid: String
    let donated: Bool
    let checked_at: String
}

/// Response từ Cloudflare Workers API
private struct DonateAPIResponse: Codable {
    let donated: Bool
}

// MARK: - Array extension for key length
private extension Array {
    var length: Int { count }
}
