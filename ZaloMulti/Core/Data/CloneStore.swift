// CloneStore.swift
// ZaloMulti
//
// State management trung tâm cho toàn bộ ứng dụng.
// Quản lý danh sách clones, CRUD operations, launch/stop.
// Pattern sao chép từ zDesk-Pro (đã kiểm chứng hoạt động)

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
        for clone in clones {
            DiagnosticLogger.debug("STORE", "  → '\(clone.name)' status=\(clone.status.rawValue) index=\(clone.cloneIndex)")
        }
        
        // Timer đồng bộ trạng thái mỗi 3 giây — giữ strong reference
        startSyncTimer()
    }
    
    /// Bắt đầu timer sync — thêm vào RunLoop.main với .common mode
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.syncRunningStatus()
            }
        }
        // Đảm bảo timer fire trong common run loop modes (khi UI đang scroll/interact)
        if let timer = syncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        DiagnosticLogger.info("STORE", "Sync timer đã khởi động")
    }
    
    // MARK: - CRUD
    
    /// Thêm clone mới
    func addClone(name: String, phone: String) {
        let nextIndex = (clones.map(\.cloneIndex).max() ?? 0) + 1
        DiagnosticLogger.info("STORE", "addClone: name='\(name)', phone='\(phone)', nextIndex=\(nextIndex)")
        
        Task {
            do {
                let clone = try await engine.createClone(
                    index: nextIndex,
                    name: name,
                    phone: phone
                )
                clones.append(clone)
                saveClones()
                DiagnosticLogger.success("STORE", "Clone '\(name)' đã thêm vào danh sách (total=\(clones.count))")
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
        DiagnosticLogger.info("STORE", "updateClone: '\(updated.name)' đã cập nhật")
    }
    
    /// Xoá clone
    func deleteClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STORE", "deleteClone: '\(clone.name)'")
        
        if processManager.isCloneRunning(clone) {
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
        
        DiagnosticLogger.info("STORE", "launchClone: '\(clone.name)' (index=\(clone.cloneIndex))")
        
        do {
            let pid = try processManager.launchClone(clone)
            clones[index].status = .running
            clones[index].processID = pid
            clones[index].lastOpenedAt = Date()
            saveClones()
            // Force UI update
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
        
        DiagnosticLogger.info("STORE", "stopClone: '\(clone.name)'")
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
    
    // MARK: - Process Sync (copy từ zDesk-Pro — đã kiểm chứng)
    
    /// Đồng bộ trạng thái clone với ProcessManager mỗi 3 giây
    /// Chạy pgrep trên BACKGROUND THREAD (Task.detached) để không block UI
    private func syncRunningStatus() {
        // Capture clone data cho background check
        let cloneSnapshots = clones.map { (id: $0.id, index: $0.cloneIndex, currentStatus: $0.status, pid: $0.processID, name: $0.name) }
        
        guard !cloneSnapshots.isEmpty else { return }
        
        Task.detached(priority: .utility) {
            // Build immutable results array trên background thread
            let results = cloneSnapshots.map { snap in
                let running = ProcessManager.checkCloneRunning(cloneIndex: snap.index, knownPID: snap.pid)
                return (id: snap.id, isRunning: running, currentName: snap.name)
            }
            
            // Apply kết quả trên MainActor
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                var changed = false
                for result in results {
                    guard let idx = self.clones.firstIndex(where: { $0.id == result.id }) else { continue }
                    
                    if self.clones[idx].status == .running && !result.isRunning {
                        DiagnosticLogger.info("SYNC", "→ '\(self.clones[idx].name)' running→stopped")
                        self.clones[idx].status = .stopped
                        self.clones[idx].processID = nil
                        changed = true
                    } else if self.clones[idx].status == .stopped && result.isRunning {
                        DiagnosticLogger.info("SYNC", "→ '\(self.clones[idx].name)' stopped→running ✅")
                        self.clones[idx].status = .running
                        changed = true
                    }
                }
                if changed {
                    self.objectWillChange.send()
                    self.saveClones()
                    DiagnosticLogger.success("SYNC", "UI đã cập nhật trạng thái")
                }
            }
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
    
    /// Đồng bộ trạng thái process khi app khởi động — copy từ zDesk-Pro
    private func syncProcessStatus() {
        DiagnosticLogger.info("STORE", "Sync process status cho \(clones.count) clones...")
        var changed = 0
        
        for i in clones.indices {
            let pidAlive = clones[i].processID != nil && processManager.isRunning(pid: clones[i].processID!)
            let pgrepAlive = ProcessManager.checkCloneRunning(cloneIndex: clones[i].cloneIndex, knownPID: nil)
            
            if pidAlive || pgrepAlive {
                clones[i].status = .running
                DiagnosticLogger.info("STORE", "  '\(clones[i].name)' → running")
            } else {
                if clones[i].status == .running { changed += 1 }
                clones[i].status = .stopped
                clones[i].processID = nil
                DiagnosticLogger.info("STORE", "  '\(clones[i].name)' → stopped")
            }
        }
        
        if changed > 0 {
            saveClones()
            DiagnosticLogger.info("STORE", "Sync xong: \(changed) clones đổi trạng thái")
        }
    }
}
