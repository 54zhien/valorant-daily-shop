import Foundation

// ============================================================================
//  SHA-1
// ============================================================================
//
//  为什么自己写一个，而不是用 CryptoKit：
//    这个包在 Windows 上跑 `swift test`（CI 的测试 job 也是），
//    CryptoKit 只有 Apple 平台有。自己实现一份，两边行为完全一致，
//    而且可以拿真机抓到的样本做回归测试。
//
//  用途只有一个：算扫码登录的 signature。
//     signature = SHA1("appid={A}&noncestr={N}&sdk_ticket={T}&timestamp={TS}")
//
//  ⚠️ SHA-1 在这个场景里不是用来保密的（材料全在客户端），
//     它只是微信那边定的协议格式，所以「SHA-1 不安全」在这里不构成问题。
// ============================================================================

public enum SHA1 {

    /// 对字符串取 SHA-1，返回 40 位小写十六进制。
    public static func hex(_ string: String) -> String {
        hex(Array(string.utf8))
    }

    /// 对字节取 SHA-1，返回 40 位小写十六进制。
    public static func hex(_ message: [UInt8]) -> String {
        digest(message).map { String(format: "%02x", $0) }.joined()
    }

    /// 标准 SHA-1（FIPS 180-1）。
    public static func digest(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        // ---- padding ----
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 {
            data.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }

        // ---- process each 512-bit chunk ----
        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = (UInt32(data[j]) << 24)
                     | (UInt32(data[j + 1]) << 16)
                     | (UInt32(data[j + 2]) << 8)
                     |  UInt32(data[j + 3])
            }
            for i in 16..<80 {
                w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A82_7999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }
                let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotl(b, 30)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        var out = [UInt8]()
        out.reserveCapacity(20)
        for h in [h0, h1, h2, h3, h4] {
            out.append(UInt8((h >> 24) & 0xFF))
            out.append(UInt8((h >> 16) & 0xFF))
            out.append(UInt8((h >> 8) & 0xFF))
            out.append(UInt8(h & 0xFF))
        }
        return out
    }

    private static func rotl(_ value: UInt32, _ bits: UInt32) -> UInt32 {
        (value << bits) | (value >> (32 - bits))
    }
}
