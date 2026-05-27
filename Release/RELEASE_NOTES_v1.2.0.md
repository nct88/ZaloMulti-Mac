## ZalỏMulti v1.2.0 — Phiên Đăng Nhập Bền Vững

### 🔥 Highlights
- **Fix mất phiên đăng nhập** — Tắt/mở clone không cần quét QR lại
- **Thanh tiến trình chi tiết** — 7 bước tạo clone hiển thị rõ ràng

### ✅ Sửa lỗi
- Fix: Mất session khi dừng/đóng clone (graceful quit thay vì force kill)
- Fix: Khôi phục macOS Keychain cho Zalo Safe Storage
- Fix: Thanh tiến trình tạo clone nhảy thẳng "Hoàn thành!" thay vì hiện từng bước

### ⚡ Cải thiện
- Cơ chế dừng clone 4 bước: Apple Event Quit → Chờ 5s → SIGTERM → SIGKILL
- Thanh tiến trình 7 bước chi tiết với delay 300ms giữa mỗi bước
- Reset progress message trước khi tạo clone mới

### 📋 Yêu cầu hệ thống
- macOS 14 (Sonoma) trở lên
- Apple Silicon hoặc Intel
- Zalo Desktop đã cài sẵn
