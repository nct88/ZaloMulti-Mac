// AvatarExtractor.swift
// ZaloMulti
//
// Trích xuất avatar + display_name từ Zalo cache data.
// Zalo lưu profile info trong Chromium cache (Partitions/zalo/Cache)
// Format: {"avatar":"https://...","display_name":"Tên User"}

import Foundation
import AppKit

/// Profile data extracted from Zalo cache
struct ZaloProfile {
    let displayName: String?
    let avatarURL: String?
}

/// Trích xuất profile info từ Zalo clone cache data
final class AvatarExtractor: @unchecked Sendable {
    
    /// Cache avatar đã download
    nonisolated(unsafe) private static var avatarCache: [Int: NSImage] = [:]
    nonisolated(unsafe) private static var profileCache: [Int: ZaloProfile] = [:]
    
    /// Trích xuất profile (avatar + display_name) từ cache
    nonisolated static func extractProfile(cloneIndex: Int) -> ZaloProfile? {
        // Check cache first
        if let cached = profileCache[cloneIndex] {
            return cached
        }
        
        let cacheDir = "\(ZaloPaths.zaloDataBase)/Data/clone\(cloneIndex)/ZaloData/Partitions/zalo/Cache/Cache_Data"
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: cacheDir),
              let files = try? fm.contentsOfDirectory(atPath: cacheDir) else {
            return nil
        }
        
        let avatarMarker = Data("\"avatar\":\"".utf8)
        let closingBrace = UInt8(ascii: "}")
        let openingBrace = UInt8(ascii: "{")
        
        // Scan cache files for profile JSON
        for file in files where file.hasSuffix("_0") {
            let filePath = "\(cacheDir)/\(file)"
            guard let data = fm.contents(atPath: filePath) else { continue }
            
            // Tìm avatar marker trong raw bytes
            guard let avatarIdx = data.range(of: avatarMarker) else { continue }
            
            // Tìm "{" trước avatar marker
            var jsonStart = avatarIdx.lowerBound
            while jsonStart > 0 {
                jsonStart -= 1
                if data[jsonStart] == openingBrace { break }
            }
            
            // Tìm "}" cuối cùng liên tiếp sau avatar (JSON closing)
            var jsonEnd = avatarIdx.upperBound
            while jsonEnd < data.count - 1 {
                if data[jsonEnd] == closingBrace {
                    // Check if next byte is also } (nested JSON)
                    if jsonEnd + 1 < data.count && data[jsonEnd + 1] == closingBrace {
                        jsonEnd += 1
                    } else {
                        break
                    }
                }
                jsonEnd += 1
            }
            
            // Extract exact JSON chunk and decode as UTF-8
            let jsonData = data[jsonStart...jsonEnd]
            guard let jsonStr = String(data: jsonData, encoding: .utf8) else { continue }
            
            // Extract avatar URL
            var avatarURL: String?
            if let range = jsonStr.range(of: #""avatar":"(https:[^"]+)""#, options: .regularExpression) {
                avatarURL = String(jsonStr[range])
                    .replacingOccurrences(of: "\"avatar\":\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "/120/", with: "/240/")
            }
            
            // Extract display_name
            var displayName: String?
            if let range = jsonStr.range(of: #""display_name":"([^"]+)""#, options: .regularExpression) {
                displayName = String(jsonStr[range])
                    .replacingOccurrences(of: "\"display_name\":\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
            
            if avatarURL != nil || displayName != nil {
                let profile = ZaloProfile(displayName: displayName, avatarURL: avatarURL)
                profileCache[cloneIndex] = profile
                DiagnosticLogger.info("PROFILE", "Clone \(cloneIndex): name='\(displayName ?? "?")' avatar=\(avatarURL != nil ? "✓" : "✗")")
                return profile
            }
        }
        
        return nil
    }
    
    /// Trích xuất avatar URL (convenience)
    nonisolated static func extractAvatarURL(cloneIndex: Int) -> String? {
        return extractProfile(cloneIndex: cloneIndex)?.avatarURL
    }
    
    /// Trích xuất display name (convenience)
    nonisolated static func extractDisplayName(cloneIndex: Int) -> String? {
        return extractProfile(cloneIndex: cloneIndex)?.displayName
    }
    
    /// Download avatar image (cached)
    static func loadAvatar(cloneIndex: Int, completion: @escaping (NSImage?) -> Void) {
        // Check memory cache
        if let cached = avatarCache[cloneIndex] {
            completion(cached)
            return
        }
        
        // Check disk cache
        let cachePath = "\(ZaloPaths.zaloDataBase)/Data/clone\(cloneIndex)/avatar_cache.jpg"
        if FileManager.default.fileExists(atPath: cachePath),
           let image = NSImage(contentsOfFile: cachePath) {
            avatarCache[cloneIndex] = image
            completion(image)
            return
        }
        
        // Extract URL and download
        guard let urlStr = extractAvatarURL(cloneIndex: cloneIndex),
              let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Save to disk cache
            try? data.write(to: URL(fileURLWithPath: cachePath))
            
            avatarCache[cloneIndex] = image
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
    
    /// Load profile + avatar together
    static func loadProfile(cloneIndex: Int, completion: @escaping (ZaloProfile?, NSImage?) -> Void) {
        let profile = extractProfile(cloneIndex: cloneIndex)
        loadAvatar(cloneIndex: cloneIndex) { image in
            completion(profile, image)
        }
    }
    
    /// Xoá cache (khi user đổi avatar/tên)
    static func clearCache(cloneIndex: Int) {
        avatarCache.removeValue(forKey: cloneIndex)
        profileCache.removeValue(forKey: cloneIndex)
        let cachePath = "\(ZaloPaths.zaloDataBase)/Data/clone\(cloneIndex)/avatar_cache.jpg"
        try? FileManager.default.removeItem(atPath: cachePath)
    }
    
    /// Xoá tất cả cache
    static func clearAllCache() {
        avatarCache.removeAll()
        profileCache.removeAll()
    }
}
