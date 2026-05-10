// ProcessManager.swift
// ZaloMulti
//
// Quản lý processes: launch, stop, monitor Zalo clone instances.

import Foundation
import AppKit

/// Quản lý processes của các Zalo clone
@MainActor
final class ProcessManager: ObservableObject {
    @Published var runningProcesses: [UUID: Int32] = [:]
    
    init() {
        DiagnosticLogger.info("PROCESS", "ProcessManager khởi tạo")
    }
    
    /// Khởi chạy một Zalo clone — sử dụng symlink switch cho ZaloData isolation
    @discardableResult
    func launchClone(_ clone: CloneAccount) throws -> Int32 {
        DiagnosticLogger.info("LAUNCH", "Bắt đầu launch clone '\(clone.name)' (index=\(clone.cloneIndex))")
        DiagnosticLogger.debug("LAUNCH", "appPath=\(clone.appPath)")
        DiagnosticLogger.debug("LAUNCH", "dataPath=\(clone.dataPath)")
        
        let binaryPath = "\(clone.appPath)/Contents/MacOS/Zalo"
        
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            DiagnosticLogger.error("LAUNCH", "Binary không tồn tại: \(binaryPath)")
            throw CloneError.zaloNotFound
        }
        
        // Kiểm tra clone đang chạy
        if let existingPID = runningProcesses[clone.id], isRunning(pid: existingPID) {
            throw CloneError.alreadyRunning
        }
        
        let fm = FileManager.default
        let realHome = NSHomeDirectory()
        
        // Tạo clone ZaloData directory
        let cloneZaloData = "\(clone.dataPath)/ZaloData"
        try? fm.createDirectory(atPath: cloneZaloData, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(clone.dataPath)/tmp", withIntermediateDirectories: true)
        
        // Đường dẫn ZaloData mặc định (Zalo hardcode path này)
        let defaultZaloData = "\(realHome)/Library/Application Support/ZaloData"
        let backupZaloData = "\(realHome)/Library/Application Support/ZaloData.original"
        
        // STEP 1: Backup ZaloData gốc (lần đầu tiên)
        if fm.fileExists(atPath: defaultZaloData) {
            let attrs = try? fm.attributesOfItem(atPath: defaultZaloData)
            let isSymlink = attrs?[.type] as? FileAttributeType == .typeSymbolicLink
            
            if !isSymlink {
                DiagnosticLogger.info("LAUNCH", "Backup ZaloData gốc → ZaloData.original")
                try? fm.moveItem(atPath: defaultZaloData, toPath: backupZaloData)
                
                if (try? fm.contentsOfDirectory(atPath: cloneZaloData))?.isEmpty ?? true {
                    try? fm.removeItem(atPath: cloneZaloData)
                    try? fm.copyItem(atPath: backupZaloData, toPath: cloneZaloData)
                }
            }
        }
        
        // STEP 2: Switch symlink ZaloData → clone data
        try? fm.removeItem(atPath: defaultZaloData)
        try fm.createSymbolicLink(atPath: defaultZaloData, withDestinationPath: cloneZaloData)
        DiagnosticLogger.info("LAUNCH", "Symlink ZaloData → \(cloneZaloData)")
        
        // Launch Zalo.orig trực tiếp (giống zDesk-Pro)
        let origBinaryPath = "\(clone.appPath)/Contents/MacOS/Zalo.orig"
        let actualBinary = fm.fileExists(atPath: origBinaryPath) ? origBinaryPath : binaryPath
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: actualBinary)
        process.currentDirectoryURL = URL(fileURLWithPath: clone.dataPath)
        
        // QUAN TRỌNG: Phải set HOME = clone.dataPath để Electron lưu session vào đúng nơi
        // Nếu không, tất cả clones sẽ dùng chung ~/Library/Application Support/Zalo (real home)
        // Dẫn đến việc đè session của nhau và bị văng đăng nhập.
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = clone.dataPath
        process.environment = env
        
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            let pid = process.processIdentifier
            runningProcesses[clone.id] = pid
            
            let cloneId = clone.id
            let cloneName = clone.name
            
            process.terminationHandler = { [weak self] proc in
                DiagnosticLogger.warning("MONITOR", "Clone '\(cloneName)' (PID \(pid)) terminated — exit code: \(proc.terminationStatus)")
                Task { @MainActor in
                    self?.runningProcesses.removeValue(forKey: cloneId)
                }
            }
            
            // Chờ 3 giây cho Zalo lock Singleton
            Task {
                try? await Task.sleep(for: .seconds(3))
                DiagnosticLogger.info("LAUNCH", "Clone '\(cloneName)' đã launch xong — symlink sẵn sàng cho clone tiếp")
            }
            
            DiagnosticLogger.success("LAUNCH", "Clone '\(clone.name)' đã launch — PID: \(pid)")
            return pid
        } catch {
            try? fm.removeItem(atPath: defaultZaloData)
            if fm.fileExists(atPath: backupZaloData) {
                try? fm.createSymbolicLink(atPath: defaultZaloData, withDestinationPath: backupZaloData)
            }
            throw CloneError.launchFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Stop Clone
    
    func stopClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STOP", "Dừng clone '\(clone.name)'")
        
        // Step 1: Gửi Apple Event quit
        let bundleID = clone.bundleID
        let script = "tell application id \"\(bundleID)\" to quit"
        let appleScript = Process()
        appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        appleScript.arguments = ["-e", script]
        appleScript.standardOutput = FileHandle.nullDevice
        appleScript.standardError = FileHandle.nullDevice
        try? appleScript.run()
        
        // Step 2: Kill bằng PID
        if let pid = runningProcesses[clone.id], isRunning(pid: pid) {
            kill(-pid, SIGTERM)
            kill(pid, SIGTERM)
        }
        
        // Step 3: pkill bằng app name
        let appName = "ZaloClone\(clone.cloneIndex).app"
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProc.arguments = ["-f", appName]
        killProc.standardOutput = FileHandle.nullDevice
        killProc.standardError = FileHandle.nullDevice
        try? killProc.run()
        killProc.waitUntilExit()
        
        runningProcesses.removeValue(forKey: clone.id)
        
        let cloneId = clone.id
        let cloneName = clone.name
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.isCloneRunning(clone) {
                DiagnosticLogger.warning("STOP", "Clone '\(cloneName)' chưa dừng → force kill")
                let forceKill = Process()
                forceKill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                forceKill.arguments = ["-9", "-f", appName]
                forceKill.standardOutput = FileHandle.nullDevice
                forceKill.standardError = FileHandle.nullDevice
                try? forceKill.run()
                forceKill.waitUntilExit()
            }
            self.runningProcesses.removeValue(forKey: cloneId)
            DiagnosticLogger.success("STOP", "Clone '\(cloneName)' đã dừng")
        }
    }
    
    func stopAllClones() {
        DiagnosticLogger.info("STOP", "Dừng tất cả clones...")
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProc.arguments = ["-f", "ZaloMulti/Clones/ZaloClone"]
        killProc.standardOutput = FileHandle.nullDevice
        killProc.standardError = FileHandle.nullDevice
        try? killProc.run()
        killProc.waitUntilExit()
        
        Task {
            try? await Task.sleep(for: .seconds(1))
            let forceKill = Process()
            forceKill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            forceKill.arguments = ["-9", "-f", "ZaloMulti/Clones/ZaloClone"]
            forceKill.standardOutput = FileHandle.nullDevice
            forceKill.standardError = FileHandle.nullDevice
            try? forceKill.run()
            forceKill.waitUntilExit()
        }
        
        runningProcesses.removeAll()
    }
    
    // MARK: - Process Status
    
    nonisolated func isRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
    
    /// Kiểm tra clone đang chạy — dùng bởi stopClone
    func isCloneRunning(_ clone: CloneAccount) -> Bool {
        if let pid = runningProcesses[clone.id], isRunning(pid: pid) {
            return true
        }
        return Self.checkCloneRunning(cloneIndex: clone.cloneIndex, knownPID: clone.processID)
    }
    
    /// Background-safe clone running check (nonisolated) — copy từ zDesk-Pro
    nonisolated static func checkCloneRunning(cloneIndex: Int, knownPID: Int32?) -> Bool {
        // Check PID first
        if let pid = knownPID, kill(pid, 0) == 0 {
            DiagnosticLogger.debug("CHECK", "clone\(cloneIndex): PID \(pid) alive")
            return true
        }
        
        // pgrep check
        let pattern = "ZaloClone\(cloneIndex).app"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", pattern]
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let found = !output.isEmpty
            DiagnosticLogger.debug("CHECK", "clone\(cloneIndex): pgrep '\(pattern)' → \(found ? "FOUND: \(output.components(separatedBy: "\n").first ?? "")" : "NOT FOUND")")
            return found
        } catch {
            DiagnosticLogger.error("CHECK", "clone\(cloneIndex): pgrep error", error: error)
            return false
        }
    }
}
