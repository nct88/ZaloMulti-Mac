// SecureConfig.swift
// ZaloMulti
//
// AES-256-GCM string decryption — bảo vệ endpoints, URLs, identifiers.
// Encrypted values được generate bởi generate_encrypted.swift

import Foundation
import CryptoKit

/// Quản lý giải mã an toàn các chuỗi nhạy cảm — AES-256-GCM
enum SecureConfig {
    
    // MARK: - Key Derivation Components (scattered)
    
    private static let _s1: [UInt8] = [0xA7, 0x3B, 0xF2, 0x19, 0x84, 0xC6, 0x5D, 0xE0]
    private static let _s2: [UInt8] = [0x72, 0x4E, 0x91, 0xAD, 0x38, 0xB5, 0x06, 0xCF]
    private static let _s3: [UInt8] = [0x53, 0x1A, 0xE8, 0x67, 0xDB, 0x40, 0x9C, 0x2F]
    private static let _s4: [UInt8] = [0x86, 0xF3, 0x14, 0x7B, 0xA2, 0x59, 0xC0, 0xED]
    
    nonisolated(unsafe) private static var _cachedKey: SymmetricKey?
    
    /// Key derived from Bundle ID + embedded salt — khác nhau mỗi app
    private static var decryptionKey: SymmetricKey {
        if let cached = _cachedKey { return cached }
        let bid = (Bundle.main.bundleIdentifier ?? "").data(using: .utf8) ?? Data()
        let salt = Data(_s1 + _s2 + _s3 + _s4)
        var hasher = SHA256()
        hasher.update(data: bid)
        hasher.update(data: salt)
        let hash = hasher.finalize()
        let key = SymmetricKey(data: hash)
        _cachedKey = key
        return key
    }
    
    // MARK: - Encrypted Values (auto-generated)
    
    static let _donateAPIBase = "bb8f9073605c42914e1391f024c93f4f5d266af92ee4540d3affef50513b13f68d2edabfe3753f51d9b111ef0291165556"
    static let _donatePageURL = "a605fc884111ec288bf43b705be7740e58fe211c3de725a35ea31b45ab92dd3fe5a12a7b6b87835da32120c1b710cc92a5756339"
    static let _fallbackDonate = "c17b5e35abc710b6b7571d98899bfc93921bb2c408c21dfe68b93779b5c6654586eee3d660529680144b8a02f7c759013d6284f9"
    static let _githubRepoPath = "6f4a452df00663f7aa72809367a9670cf6a8c5d6dcf145cda12cacf1b034bf6804aedcdcf7e9c7db407bd31aa3077e"
    static let _githubAPIBase = "6d39f3c393b6b323c9290033fc5d9c86341caa48d5af203d6d568cb9ff3d16782607a2644b7a7d2ae9e66f34dc12ad981660c1c0472430389f"
    static let _socialMessenger = "a5c02bce9aa51fe0461a4a787643f4af86666a3a81ce5cb66f47683634f54fd13996987d5b725ff4fadf2c3790bbba10ac2df9d39e"
    static let _socialTelegram = "2af5ac2e02641265182b8e3e2adb8ce10d514cf8a682042929c8356f9d164f628b799bcdcec05ff6d8284563e3c946705b320ce287"
    static let _socialZalo = "f2c3cea11d8c11548fd497a2c46d87ba6e0b2311956041b6983727f67e8492758e3fe7ef9c782e1c8778419208ecfc211037460cede47d57"
    static let _socialDonate = "a1a2303a4a872c904aae288e8dd2bd819255efe3da7611568b6e5fbb1c757d5db47dcb2fe925d932698cb0aab0f8068415f72920"
    static let _logSubsystem = "a1eb065b62bce96d98cc730f8f36984753b813dd212d4299909bbeb0e63ff1366d35796847a918b1468e8fa0d06bfff92bbc2421f37e"
    static let _workersDev = "5b7ebdf6e0e933cdb28e52a06ff73ff53a4ff2b87e88a659f4b2714dafd3a671a18d2a105f12cd"
    static let _integrityDonate = "5085d06603e19374fafbeaa58213ef7dc93a207c6347e88314b05647b20d1966cf71"
    
    // MARK: - Public Accessors
    
    static var donateAPIBase: String { decrypt(_donateAPIBase) ?? "" }
    static var donatePageURL: String { decrypt(_donatePageURL) ?? "" }
    static var fallbackDonate: String { decrypt(_fallbackDonate) ?? "" }
    static var githubRepoPath: String { decrypt(_githubRepoPath) ?? "" }
    static var githubAPIURL: String {
        let base = decrypt(_githubAPIBase) ?? ""
        let repo = decrypt(_githubRepoPath) ?? ""
        return "\(base)\(repo)/releases/latest"
    }
    static var socialMessenger: String { decrypt(_socialMessenger) ?? "" }
    static var socialTelegram: String { decrypt(_socialTelegram) ?? "" }
    static var socialZalo: String { decrypt(_socialZalo) ?? "" }
    static var socialDonate: String { decrypt(_socialDonate) ?? "" }
    static var logSubsystem: String { decrypt(_logSubsystem) ?? "" }
    
    // MARK: - Integrity Validation Components
    
    static var workersDev: String { decrypt(_workersDev) ?? "" }
    static var integrityDonate: String { decrypt(_integrityDonate) ?? "" }
    
    // MARK: - Decryption
    
    /// Decrypt AES-256-GCM hex string → plaintext
    /// Format: nonce(12 bytes) + ciphertext(N bytes) + tag(16 bytes)
    static func decrypt(_ hexString: String) -> String? {
        guard let combined = Data(hexString: hexString),
              combined.count > 28 else { return nil }
        
        let nonceData = combined.prefix(12)
        let ciphertext = combined[combined.index(combined.startIndex, offsetBy: 12)..<combined.index(combined.endIndex, offsetBy: -16)]
        let tag = combined.suffix(16)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: .init(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let plainData = try AES.GCM.open(sealedBox, using: decryptionKey)
            return String(data: plainData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Data Hex Extension
extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
