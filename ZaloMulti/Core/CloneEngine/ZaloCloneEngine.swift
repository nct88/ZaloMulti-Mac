// ZaloCloneEngine.swift
// ZaloMulti
//
// Logic cốt lõi: detect Zalo gốc, copy bundle, đổi Bundle ID, re-sign.

import Foundation
import AppKit

/// Constants cho ZaloCloneEngine
enum ZaloPaths {
    static let zaloSourcePath = "/Applications/Zalo.app"
    static let zaloDataBase = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti"
    static let cloneAppBase = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti/Clones"
    static let originalBundleID = "com.vng.zalo"
    static let originalSendSocket = "/tmp/socketzalosend2021"
    static let originalRecvSocket = "/tmp/socketzalorecv2021"
}

/// Engine chính quản lý việc tạo và xoá Zalo clone
@MainActor
final class ZaloCloneEngine: ObservableObject {
    
    @Published var isProcessing = false
    @Published var progressMessage = ""
    
    // MARK: - Detect Zalo Source
    
    nonisolated func detectSourceZalo() -> (installed: Bool, version: String?, bundleID: String?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ZaloPaths.zaloSourcePath) else {
            DiagnosticLogger.warning("DETECT", "Zalo KHÔNG tìm thấy tại \(ZaloPaths.zaloSourcePath)")
            return (false, nil, nil)
        }
        
        let plistPath = "\(ZaloPaths.zaloSourcePath)/Contents/Info.plist"
        guard let plist = NSDictionary(contentsOfFile: plistPath) else {
            DiagnosticLogger.warning("DETECT", "Không đọc được Info.plist tại \(plistPath)")
            return (true, nil, nil)
        }
        
        let version = plist["CFBundleShortVersionString"] as? String
        let bundleID = plist["CFBundleIdentifier"] as? String
        
        DiagnosticLogger.info("DETECT", "Zalo OK — version=\(version ?? "?"), bundleID=\(bundleID ?? "?")")
        return (true, version, bundleID)
    }
    
    nonisolated var sourceZaloVersion: String? {
        detectSourceZalo().version
    }
    
    nonisolated var isElectronApp: Bool {
        let exists = FileManager.default.fileExists(
            atPath: "\(ZaloPaths.zaloSourcePath)/Contents/Resources/app.asar"
        )
        DiagnosticLogger.debug("DETECT", "Electron check: app.asar \(exists ? "tồn tại" : "KHÔNG tồn tại")")
        return exists
    }
    
    // MARK: - Create Clone
    
    func createClone(index: Int, name: String, phone: String = "") async throws -> CloneAccount {
        let clonePath = "\(ZaloPaths.cloneAppBase)/ZaloClone\(index).app"
        let bundleID = "\(ZaloPaths.originalBundleID).clone\(index)"
        let dataPath = "\(ZaloPaths.zaloDataBase)/Data/clone\(index)"
        
        DiagnosticLogger.info("CREATE", "Bắt đầu tạo clone #\(index): '\(name)'")
        
        isProcessing = true
        progressMessage = "Đang chuẩn bị..."
        try? await Task.sleep(for: .milliseconds(400))
        
        do {
            progressMessage = "Tạo thư mục dữ liệu..."
            try Self.createDirectories(dataPath: dataPath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Sao chép Zalo app (APFS clone)..."
            try await Self.copyBundle(from: ZaloPaths.zaloSourcePath, to: clonePath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Đổi Bundle Identifier..."
            try Self.modifyBundleID(appPath: clonePath, newBundleID: bundleID)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Đang vá Socket (app.asar)..."
            try Self.patchAsarSockets(appPath: clonePath, instanceIndex: index)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Tạo launcher wrapper..."
            try Self.createWrapperScript(appPath: clonePath, dataPath: dataPath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Xoá quarantine..."
            try Self.removeQuarantine(appPath: clonePath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Re-sign ứng dụng..."
            try await Self.resignApp(appPath: clonePath)
            try? await Task.sleep(for: .milliseconds(300))
            
            isProcessing = false
            progressMessage = "Hoàn thành!"
            
            let account = CloneAccount(
                name: name,
                phoneNumber: phone,
                cloneIndex: index,
                bundleID: bundleID,
                appPath: clonePath,
                dataPath: dataPath,
                status: .stopped,
                avatarColor: CloneAccount.colorForIndex(index),
                createdAt: Date()
            )
            
            DiagnosticLogger.success("CREATE", "✅ Clone '\(name)' tạo thành công!")
            return account
            
        } catch {
            isProcessing = false
            progressMessage = "Lỗi: \(error.localizedDescription)"
            DiagnosticLogger.error("CREATE", "❌ Tạo clone THẤT BẠI", error: error)
            throw error
        }
    }
    
    // MARK: - Delete Clone
    
    nonisolated func deleteClone(_ clone: CloneAccount) throws {
        DiagnosticLogger.info("DELETE", "Xoá clone '\(clone.name)' (index=\(clone.cloneIndex))")
        let fm = FileManager.default
        
        if fm.fileExists(atPath: clone.appPath) {
            try fm.removeItem(atPath: clone.appPath)
        }
        if fm.fileExists(atPath: clone.dataPath) {
            try fm.removeItem(atPath: clone.dataPath)
        }
        DiagnosticLogger.success("DELETE", "Clone '\(clone.name)' đã xoá hoàn toàn")
    }
    
    // MARK: - Private Static Methods
    
    private nonisolated static func createDirectories(dataPath: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: ZaloPaths.cloneAppBase, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dataPath, withIntermediateDirectories: true)
        for subdir in ["Library/Application Support", "Library/Caches", "Library/Preferences", "Documents", "tmp"] {
            try fm.createDirectory(atPath: "\(dataPath)/\(subdir)", withIntermediateDirectories: true)
        }
    }
    
    private nonisolated static func copyBundle(from source: String, to destination: String) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination) { try fm.removeItem(atPath: destination) }
        
        let cloneProcess = Process()
        cloneProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
        cloneProcess.arguments = ["-c", "-R", source, destination]
        let pipe = Pipe()
        cloneProcess.standardError = pipe
        try cloneProcess.run()
        cloneProcess.waitUntilExit()
        
        if cloneProcess.terminationStatus != 0 {
            let rsyncProcess = Process()
            rsyncProcess.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            rsyncProcess.arguments = ["-a", "--quiet", source + "/", destination + "/"]
            try rsyncProcess.run()
            rsyncProcess.waitUntilExit()
            guard rsyncProcess.terminationStatus == 0 else {
                throw CloneError.copyFailed("rsync thất bại với exit code \(rsyncProcess.terminationStatus)")
            }
        }
    }
    
    private nonisolated static func createWrapperScript(appPath: String, dataPath: String) throws {
        let binaryPath = "\(appPath)/Contents/MacOS/Zalo"
        let origBinaryPath = "\(appPath)/Contents/MacOS/Zalo.orig"
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: origBinaryPath) {
            try fm.moveItem(atPath: binaryPath, toPath: origBinaryPath)
        }
        
        let script = """
        #!/bin/bash
        export HOME="\(dataPath)"
        exec "$(dirname "$0")/Zalo.orig" "$@"
        """
        try script.write(toFile: binaryPath, atomically: true, encoding: .utf8)
        
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", binaryPath]
        try chmodProcess.run()
        chmodProcess.waitUntilExit()
    }
    
    private nonisolated static func modifyBundleID(appPath: String, newBundleID: String) throws {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard FileManager.default.fileExists(atPath: plistPath) else { throw CloneError.plistNotFound }
        try runPlistBuddy(plistPath: plistPath, command: "Set :CFBundleIdentifier \(newBundleID)")
        _ = try? runPlistBuddy(plistPath: plistPath, command: "Delete :ElectronAsarIntegrity")
    }
    
    private nonisolated static func runPlistBuddy(plistPath: String, command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        process.arguments = ["-c", command, plistPath]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CloneError.plistWriteFailed }
    }
    
    // MARK: - Patch ASAR
    
    private nonisolated static func patchAsarSockets(appPath: String, instanceIndex: Int) throws {
        let asarPath = "\(appPath)/Contents/Resources/app.asar"
        
        guard FileManager.default.fileExists(atPath: asarPath) else {
            return
        }
        
        var data = try Data(contentsOf: URL(fileURLWithPath: asarPath))
        
        let sendOld = ZaloPaths.originalSendSocket
        let recvOld = ZaloPaths.originalRecvSocket
        
        let indexStr = String(format: "%04d", 2000 + instanceIndex)
        let sendNew = "/tmp/socketzalosend\(indexStr)"
        let recvNew = "/tmp/socketzalorecv\(indexStr)"
        
        assert(sendOld.count == sendNew.count, "Socket string length mismatch!")
        assert(recvOld.count == recvNew.count, "Socket string length mismatch!")
        
        data = binaryReplace(in: data, find: sendOld, replace: sendNew)
        data = binaryReplace(in: data, find: recvOld, replace: recvNew)
        
        try data.write(to: URL(fileURLWithPath: asarPath))
    }
    
    private nonisolated static func binaryReplace(in data: Data, find: String, replace: String) -> Data {
        guard let findData = find.data(using: .utf8),
              let replaceData = replace.data(using: .utf8) else { return data }
        
        var result = data
        var searchRange = result.startIndex..<result.endIndex
        
        while let range = result.range(of: findData, in: searchRange) {
            result.replaceSubrange(range, with: replaceData)
            searchRange = range.upperBound..<result.endIndex
        }
        
        return result
    }
    
    private nonisolated static func removeQuarantine(appPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-r", "-d", "com.apple.quarantine", appPath]
        try process.run()
        process.waitUntilExit()
    }
    
    private nonisolated static func resignApp(appPath: String) async throws {
        let fm = FileManager.default
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        if let contents = try? fm.contentsOfDirectory(atPath: frameworksDir) {
            for item in contents {
                let itemPath = "\(frameworksDir)/\(item)"
                if item.hasSuffix(".framework") || item.hasSuffix(".app") {
                    try runCodesign(path: itemPath, deep: true)
                }
            }
        }
        try runCodesign(path: appPath, deep: true, noStrict: true)
    }
    
    private nonisolated static func runCodesign(path: String, deep: Bool = false, noStrict: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        var args = ["--force", "--sign", "-"]
        if deep { args.insert("--deep", at: 1) }
        if noStrict { args.append("--no-strict") }
        args.append(path)
        process.arguments = args
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CloneError.codesignFailed(errorMessage)
        }
    }
}

// MARK: - Errors
enum CloneError: LocalizedError, Sendable {
    case zaloNotFound
    case copyFailed(String)
    case plistNotFound
    case plistWriteFailed
    case codesignFailed(String)
    case launchFailed(String)
    case alreadyRunning
    
    var errorDescription: String? {
        switch self {
        case .zaloNotFound:       return "Không tìm thấy Zalo tại /Applications/Zalo.app"
        case .copyFailed(let e):  return "Lỗi sao chép: \(e)"
        case .plistNotFound:      return "Không tìm thấy Info.plist"
        case .plistWriteFailed:   return "Không thể ghi Info.plist"
        case .codesignFailed(let e): return "Lỗi ký mã: \(e)"
        case .launchFailed(let e):   return "Lỗi khởi chạy: \(e)"
        case .alreadyRunning:     return "Clone này đang chạy"
        }
    }
}
