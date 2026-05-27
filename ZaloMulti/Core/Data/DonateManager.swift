// DonateManager.swift
// ZaloMulti (Open Source Version)
//
// Phiên bản mã nguồn mở đã loại bỏ tính năng theo dõi HWID và popup donate.

import Foundation

@MainActor
final class DonateManager {
    static func checkAndPromptDonate() {
        // Trong bản build mã nguồn mở, không hiện popup donate
        DiagnosticLogger.success("DONATE", "Open Source Version - Bỏ qua check donate")
    }
}
