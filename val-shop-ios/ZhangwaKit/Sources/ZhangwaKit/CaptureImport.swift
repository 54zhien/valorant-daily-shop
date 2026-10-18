import Foundation

/// 解析抓包产物。
///
/// 支持三种输入：
/// 1. `capture/frida_okhttp_dump.js` 产出的 **`mval_session.json`** —— 推荐，含 `ct`，App 拿到后可自刷新
/// 2. 同一个脚本产出的 ndjson 日志（每条一行 JSON：REQ/RESP/SESSION）
/// 3. `capture/mitm_zhangwa.py` 产出的 jsonl
public enum CaptureImporter {

    public struct Endpoint: Identifiable, Sendable {
        public let id: String
        public let url: String
        public let methods: [String]
        public let sampleBody: String?
        public let sampleResponse: String?

        public init(url: String, methods: [String],
                    sampleBody: String?, sampleResponse: String?) {
            self.id = url
            self.url = url
            self.methods = methods
            self.sampleBody = sampleBody
            self.sampleResponse = sampleResponse
        }

        /// 猜测这是不是商店接口
        public var looksLikeStore: Bool {
            let u = url.lowercased()
            return u.contains("store") || u.contains("shop")
                || u.contains("commodity") || u.contains("goods")
        }
    }

    // MARK: 会话

    /// 从任意抓包文件里提取登录态。
    public static func session(fromFileAt path: String) throws -> ZhangwaSession {
        let url = URL(fileURLWithPath: path)
        let text = try String(contentsOf: url, encoding: .utf8)

        // 1) 纯 session json（单对象）
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["user_id"] != nil || obj["ct"] != nil {
            return try ZhangwaSession.from(sessionJSON: data)
        }

        var bestCookie = ""
        var bestScore = -1
        var bestSession: ZhangwaSession?

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // 2) 日志里的 "Cookie: xxx"
            if !line.hasPrefix("{"),
               let range = line.range(of: "Cookie:") {
                let candidate = String(line[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                let score = cookieScore(candidate)
                if score > bestScore {
                    bestScore = score
                    bestCookie = candidate
                }
                continue
            }

            guard line.hasPrefix("{"),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // 3) SESSION 记录
            if (obj["kind"] as? String) == "SESSION" || obj["user_id"] != nil {
                if let s = try? ZhangwaSession.from(sessionJSON: data), s.isValid {
                    bestSession = s
                    break
                }
            }

            guard (obj["dir"] as? String ?? "REQ") == "REQ" else { continue }

            var cookie = obj["cookie"] as? String
            if cookie == nil, let dict = obj["cookies"] as? [String: Any] {
                cookie = dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
            }
            if cookie == nil, let headers = obj["headers"] as? [String: Any] {
                for (k, v) in headers where k.lowercased() == "cookie" {
                    cookie = v as? String
                    break
                }
            }
            if let cookie, !cookie.isEmpty {
                let score = cookieScore(cookie)
                if score > bestScore {
                    bestScore = score
                    bestCookie = cookie
                }
            }
        }

        if let s = bestSession, s.isValid { return s }
        if !bestCookie.isEmpty { return ZhangwaSession.from(cookieHeader: bestCookie) }
        throw ZhangwaError.capture("没找到登录态（既没有 session 记录，也没有带鉴权字段的 Cookie）")
    }

    private static func cookieScore(_ cookie: String) -> Int {
        ["clientType", "acctype", "userId", "tid", "openid", "access_token"]
            .reduce(0) { $0 + (cookie.contains($1) ? 1 : 0) }
    }

    // MARK: 接口清单

    public static func endpoints(fromFileAt path: String) throws -> [Endpoint] {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)

        var order: [String] = []
        var methods: [String: Set<String>] = [:]
        var bodies: [String: String] = [:]
        var responses: [String: String] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("{"),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            guard let url = obj["url"] as? String, url.contains("/go/") else { continue }
            let key = url.split(separator: "?").first.map(String.init) ?? url
            if methods[key] == nil {
                methods[key] = []
                order.append(key)
            }

            if (obj["dir"] as? String) == "REQ" {
                methods[key, default: []].insert((obj["method"] as? String) ?? "?")
                if bodies[key] == nil, let b = obj["body"] as? String {
                    bodies[key] = String(b.prefix(500))
                }
            } else if responses[key] == nil, let r = obj["body"] as? String {
                responses[key] = String(r.prefix(800))
            }
        }

        return order.map { key in
            Endpoint(url: key,
                     methods: methods[key].map { Array($0).sorted() } ?? [],
                     sampleBody: bodies[key],
                     sampleResponse: responses[key])
        }
    }
}
