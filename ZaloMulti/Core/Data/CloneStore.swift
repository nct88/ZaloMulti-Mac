// CloneStore.swift
// ZaloMulti
//
// State management trung tâm cho toàn bộ ứng dụng.
// Quản lý danh sách clones, CRUD operations, launch/stop.
//
// ⚡ Performance: sync dùng kill(pid,0) thay vì pgrep — không spawn process.
//    pgrep chỉ dùng 1 lần duy nhất khi startup để recover orphan processes.

import Foundation
import SwiftUI

@MainActor
class CloneStore: ObservableObject {
    
    // MARK: - Published Properties
    @Published var clones: [CloneAccount] = []
    @Published var showAddCloneSheet = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // MARK: - Dependencies
    let engine = ZaloCloneEngine()
    let processManager = ProcessManager()
    
    // MARK: - Persistence
    private let storageKey = "clone_accounts_v1"
    private var syncTimer: Timer?
    
    init() {
        DiagnosticLogger.info("STORE", "CloneStore khởi tạo...")
        loadClones()
        syncProcessStatus()
        DiagnosticLogger.info("STORE", "Đã load \(clones.count) clones từ storage")
        
        // Timer đồng bộ trạng thái mỗi 3 giây — dùng kill(pid,0) thay vì pgrep
        startSyncTimer()
    }
    
    // Timer cleanup: weak self in closure handles lifecycle
    /// Timer sync — dùng kill(pid,0) O(1) thay vì pgrep O(n) process spawning
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.syncRunningStatus()
            }
        }
        if let timer = syncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    // MARK: - CRUD
    
    /// Thêm clone mới
    func addClone(name: String, phone: String) {
        let nextIndex = (clones.map(\.cloneIndex).max() ?? 0) + 1
        DiagnosticLogger.info("STORE", "addClone: name='\(name)', nextIndex=\(nextIndex)")
        
        Task {
            do {
                let clone = try await engine.createClone(
                    index: nextIndex,
                    name: name,
                    phone: phone
                )
                clones.append(clone)
                saveClones()
                DiagnosticLogger.success("STORE", "Clone '\(name)' đã thêm (total=\(clones.count))")
            } catch {
                self.errorMessage = error.localizedDescription
                self.showError = true
                DiagnosticLogger.error("STORE", "addClone thất bại", error: error)
            }
        }
    }
    
    /// Cập nhật thông tin clone
    func updateClone(_ updated: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == updated.id }) else { return }
        clones[index] = updated
        saveClones()
    }
    
    /// Xoá clone
    func deleteClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STORE", "deleteClone: '\(clone.name)'")
        
        // Dùng PID check thay vì pgrep
        if let pid = clone.processID, ProcessManager.isRunning(pid: pid) {
            processManager.stopClone(clone)
        }
        
        do {
            try engine.deleteClone(clone)
        } catch {
            errorMessage = "Lỗi xoá files: \(error.localizedDescription)"
            showError = true
        }
        
        clones.removeAll { $0.id == clone.id }
        saveClones()
    }
    
    // MARK: - Launch / Stop
    
    func launchClone(_ clone: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == clone.id }) else { return }
        
        do {
            let pid = try processManager.launchClone(clone)
            clones[index].status = .running
            clones[index].processID = pid
            clones[index].lastOpenedAt = Date()
            saveClones()
            objectWillChange.send()
            DiagnosticLogger.success("STORE", "Clone '\(clone.name)' đang chạy — PID=\(pid)")
        } catch {
            if case CloneError.alreadyRunning = error {
                clones[index].status = .running
                saveClones()
                objectWillChange.send()
            } else {
                errorMessage = error.localizedDescription
                showError = true
                DiagnosticLogger.error("STORE", "launchClone thất bại", error: error)
            }
        }
    }
    
    func stopClone(_ clone: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == clone.id }) else { return }
        
        processManager.stopClone(clone)
        clones[index].status = .stopped
        clones[index].processID = nil
        saveClones()
        objectWillChange.send()
    }
    
    func stopAllClones() {
        DiagnosticLogger.info("STORE", "stopAllClones — \(clones.count) clones")
        
        // Gửi Apple Event quit cho từng clone
        for clone in clones where clone.status == .running {
            let script = "tell application id \"\(clone.bundleID)\" to quit"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
        }
        
        processManager.stopAllClones()
        for i in clones.indices {
            clones[i].status = .stopped
            clones[i].processID = nil
        }
        saveClones()
        objectWillChange.send()
    }
    
    // MARK: - Statistics
    
    var runningCount: Int {
        clones.filter { $0.status == .running }.count
    }
    
    var totalCount: Int {
        clones.count
    }
    
    // MARK: - Process Sync (⚡ Optimized — kill(pid,0) thay vì pgrep)
    
    /// Đồng bộ trạng thái — dùng kill(pid,0) O(1) syscall
    /// Không spawn process → không tốn memory → Apple Silicon friendly
    private func syncRunningStatus() {
        var changed = false
        
        for i in clones.indices {
            let clone = clones[i]
            
            if clone.status == .running {
                // Kiểm tra bằng kill(pid,0) — O(1) syscall, không spawn process
                if let pid = clone.processID {
                    if !ProcessManager.isRunning(pid: pid) {
                        clones[i].status = .stopped
                        clones[i].processID = nil
                        changed = true
                        DiagnosticLogger.info("SYNC", "'\(clone.name)' running→stopped (PID \(pid) exited)")
                    }
                } else {
                    // Không có PID → đánh dấu stopped
                    clones[i].status = .stopped
                    changed = true
                }
            }
            // Không cần check stopped→running ở đây vì launch luôn set PID
        }
        
        if changed {
            objectWillChange.send()
            saveClones()
        }
    }
    
    // MARK: - Persistence
    
    func saveClones() {
        do {
            let data = try JSONEncoder().encode(clones)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            DiagnosticLogger.error("STORE", "saveClones FAILED", error: error)
        }
    }
    
    private func loadClones() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            clones = try JSONDecoder().decode([CloneAccount].self, from: data)
        } catch {
            DiagnosticLogger.error("STORE", "loadClones: decode FAILED", error: error)
        }
    }
    
    /// Startup sync — dùng kill(pid,0) cho PID đã biết, pgrep chỉ cho orphan recovery
    private func syncProcessStatus() {
        DiagnosticLogger.info("STORE", "Sync process status cho \(clones.count) clones...")
        var changed = 0
        
        for i in clones.indices {
            if let pid = clones[i].processID, ProcessManager.isRunning(pid: pid) {
                // PID vẫn sống → running
                clones[i].status = .running
            } else {
                // PID không có hoặc đã chết → kiểm tra orphan bằng pgrep (1 lần duy nhất)
                let orphanAlive = ProcessManager.checkCloneRunning(
                    cloneIndex: clones[i].cloneIndex, knownPID: nil
                )
                if orphanAlive {
                    clones[i].status = .running
                    DiagnosticLogger.info("STORE", "  '\(clones[i].name)' → running (orphan recovered)")
                } else {
                    if clones[i].status == .running { changed += 1 }
                    clones[i].status = .stopped
                    clones[i].processID = nil
                }
            }
        }
        
        if changed > 0 {
            saveClones()
        }
    }
}
