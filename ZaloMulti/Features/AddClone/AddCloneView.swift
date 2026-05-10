// AddCloneView.swift
// ZaloMulti
//
// Sheet thêm tài khoản clone mới — với progress bar inline

import SwiftUI

struct AddCloneView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: CloneStore
    
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var isCreating = false
    @State private var createComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Thêm tài khoản Clone")
                    .font(.headline)
                Spacer()
                Button("Huỷ") { dismiss() }
                    .keyboardShortcut(.escape)
                    .disabled(isCreating)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Thông tin tài khoản
                    GroupBox("Thông tin tài khoản") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledField("Tên hiển thị", text: $name,
                                         placeholder: "VD: Business, Shop Online...")
                            LabeledField("Số điện thoại", text: $phoneNumber,
                                         placeholder: "0901234567")
                            
                            // Progress bar ngay dưới SĐT (#3)
                            if isCreating {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(store.engine.progressMessage)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    ProgressView(value: progressValue)
                                        .progressViewStyle(.linear)
                                        .tint(.accentColor)
                                    
                                    Text(progressStep)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            
                            if createComplete {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Tạo clone thành công!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .fontWeight(.semibold)
                                }
                                .padding(.top, 4)
                                .transition(.opacity)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer — chỉ buttons
            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }
                    .keyboardShortcut(.escape)
                    .disabled(isCreating)
                Button(createComplete ? "Đóng" : "Tạo Clone") {
                    if createComplete {
                        dismiss()
                    } else {
                        createClone()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || isCreating)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 460, height: 340)
    }
    
    private var progressStep: String {
        let msg = store.engine.progressMessage
        if msg.contains("chuẩn bị") { return "Bước 1/6 — Chuẩn bị" }
        if msg.contains("thư mục") { return "Bước 1/6 — Tạo thư mục" }
        if msg.contains("Sao chép") { return "Bước 2/6 — Sao chép ứng dụng" }
        if msg.contains("Bundle") { return "Bước 3/6 — Đổi Bundle ID" }
        if msg.contains("wrapper") || msg.contains("launcher") { return "Bước 4/6 — Tạo launcher" }
        if msg.contains("quarantine") { return "Bước 5/6 — Xoá quarantine" }
        if msg.contains("sign") { return "Bước 6/6 — Ký mã ứng dụng" }
        if msg.contains("Hoàn thành") { return "Hoàn thành!" }
        return ""
    }
    
    private var progressValue: Double {
        let msg = store.engine.progressMessage
        if msg.contains("thư mục") || msg.contains("chuẩn bị") { return 1.0/6.0 }
        if msg.contains("Sao chép") { return 2.0/6.0 }
        if msg.contains("Bundle") { return 3.0/6.0 }
        if msg.contains("wrapper") || msg.contains("launcher") { return 4.0/6.0 }
        if msg.contains("quarantine") { return 5.0/6.0 }
        if msg.contains("sign") { return 5.5/6.0 }
        if msg.contains("Hoàn thành") { return 1.0 }
        return 0.1
    }
    
    private func createClone() {
        withAnimation { isCreating = true }
        
        Task {
            do {
                let nextIndex = (store.clones.map(\.cloneIndex).max() ?? 0) + 1
                let clone = try await store.engine.createClone(
                    index: nextIndex,
                    name: name,
                    phone: phoneNumber
                )
                store.clones.append(clone)
                store.saveClones()
                withAnimation {
                    isCreating = false
                    createComplete = true
                }
                // Auto close sau 1.5s
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            } catch {
                withAnimation { isCreating = false }
                store.errorMessage = error.localizedDescription
                store.showError = true
            }
        }
    }
}

// MARK: - Labeled Text Field
struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
