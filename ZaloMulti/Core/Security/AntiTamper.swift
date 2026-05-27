// AntiTamper.swift
// ZaloMulti
//
// Chống debug, inject, tamper — multi-layer protection.
// Chạy khi app khởi động và periodic check.

import Foundation
import Darwin
import AppKit

/// Multi-layer protection chống reverse engineering
enum AntiTamper {
    
    // MARK: - Anti-Debugger
    
    /// Phát hiện debugger bằng sysctl (P_TRACED flag)
    static var isDebuggerAttached: Bool {
        #if DEBUG
        return false
        #else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }
    
    /// Chặn debugger attach — gọi 1 lần khi app khởi động
    static func denyDebuggerAttach() {
        #if !DEBUG
        let ptraceVal: CInt = 31 // PT_DENY_ATTACH
        typealias PtraceFunc = @convention(c) (CInt, pid_t, CInt, CInt) -> CInt
        if let handle = dlopen("/usr/lib/libc.dylib", RTLD_NOW),
           let sym = dlsym(handle, "ptrace") {
            let ptrace = unsafeBitCast(sym, to: PtraceFunc.self)
            _ = ptrace(ptraceVal, 0, 0, 0)
            dlclose(handle)
        }
        #endif
    }
    
    // MARK: - Code Integrity (CodeSignature Verification)
    
    /// Kiểm tra app có bị sửa đổi binary
    static var isCodeSignatureValid: Bool {
        #if DEBUG
        return true
        #else
        var staticCode: SecStaticCode?
        let mainBundleURL = Bundle.main.bundleURL as CFURL
        guard SecStaticCodeCreateWithPath(mainBundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
        #endif
    }
    
    // MARK: - DYLD Injection Detection
    
    /// Phát hiện thư viện bị inject (Frida, Cycript, Substrate...)
    static var hasInjectedLibraries: Bool {
        #if DEBUG
        return false
        #else
        let suspicious = ["frida", "cycript", "substrate", "substitute", "inject",
                          "libReveal", "FLEXing", "FLEX"]
        let count = _dyld_image_count()
        for i in 0..<count {
            if let name = _dyld_get_image_name(i) {
                let path = String(cString: name).lowercased()
                for lib in suspicious {
                    if path.contains(lib.lowercased()) { return true }
                }
            }
        }
        return false
        #endif
    }
    
    // MARK: - Environment Variable Check
    
    /// Kiểm tra biến môi trường injection
    static var hasSuspiciousEnvironment: Bool {
        #if DEBUG
        return false
        #else
        let envVars = ["DYLD_INSERT_LIBRARIES", "DYLD_FORCE_FLAT_NAMESPACE",
                       "_MSSafeMode", "SUBSTRATE_PREFIX", "DYLD_PRINT_TO_FILE"]
        for envVar in envVars {
            if getenv(envVar) != nil { return true }
        }
        return false
        #endif
    }
    
    // MARK: - Reverse Engineering Tool Detection
    
    /// Phát hiện công cụ phân tích đang chạy
    static var hasAnalysisToolsRunning: Bool {
        #if DEBUG
        return false
        #else
        let tools = ["Hopper", "Ghidra", "IDA", "lldb", "dtrace",
                     "frida-server", "Proxyman", "Charles"]
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-ax", "-o", "comm"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            for tool in tools {
                if output.contains(tool.lowercased()) { return true }
            }
        } catch {}
        
        return false
        #endif
    }
    
    // MARK: - Combined Security Check
    
    /// Chạy tất cả kiểm tra — trả về true nếu an toàn
    static func performFullCheck() -> Bool {
        #if DEBUG
        return true
        #else
        if isDebuggerAttached { return false }
        if hasInjectedLibraries { return false }
        if hasSuspiciousEnvironment { return false }
        if !isCodeSignatureValid { return false }
        return true
        #endif
    }
    
    /// Khởi tạo bảo vệ khi app start — gọi từ App.init()
    static func initialize() {
        #if !DEBUG
        denyDebuggerAttach()
        
        // Periodic check mỗi 30 giây
        DispatchQueue.global(qos: .utility).async {
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                if !performFullCheck() {
                    // Phát hiện tampering — silent exit
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            RunLoop.current.run()
        }
        #endif
    }
}
