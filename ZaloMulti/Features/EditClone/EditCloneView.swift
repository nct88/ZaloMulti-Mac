// EditCloneView.swift
// ZaloMulti
//
// Sheet chỉnh sửa thông tin clone

import SwiftUI

struct EditCloneView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store = CloneStore.shared
    
    let clone: CloneAccount
    
    @State private var name: String
    @State private var phoneNumber: String
    
    init(clone: CloneAccount) {
        self.clone = clone
        _name = State(initialValue: clone.name)
        _phoneNumber = State(initialValue: clone.phoneNumber)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chỉnh sửa — \(clone.name)")
                    .font(.headline)
                Spacer()
                Button("Huỷ") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Thông tin tài khoản") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledField("Tên hiển thị", text: $name,
                                        placeholder: "VD: Business, Shop Online...")
                            LabeledField("Số điện thoại", text: $phoneNumber,
                                        placeholder: "0901234567")
                        }
                        .padding(8)
                    }
                    
                    GroupBox("Chi tiết Clone") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Bundle ID", value: clone.bundleID)
                            InfoRow(label: "Đường dẫn App", value: clone.appPath)
                            InfoRow(label: "Thư mục Data", value: clone.dataPath)
                            InfoRow(label: "Ngày tạo", value: clone.createdAt.formatted(date: .abbreviated, time: .shortened))
                            if let lastOpened = clone.lastOpenedAt {
                                InfoRow(label: "Mở lần cuối", value: lastOpened.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }
                Button("Lưu") { saveChanges() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }
    
    private func saveChanges() {
        var updated = clone
        updated.name = name
        updated.phoneNumber = phoneNumber
        store.updateClone(updated)
        dismiss()
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
    }
}
