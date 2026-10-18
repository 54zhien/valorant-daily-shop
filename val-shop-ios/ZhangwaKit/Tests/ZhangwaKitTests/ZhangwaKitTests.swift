import Testing
import Foundation
@testable import ZhangwaKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Swift Testing（Apple 现在推荐的测试框架），全部在 MainActor 上跑，
/// 因为 `ZhangwaClient` 是 @MainActor 隔离的。
@Suite("掌瓦协议层")
@MainActor
struct ZhangwaKitTests {

    // MARK: - 夹具

    private func qqSession() -> ZhangwaSession {
        var s = ZhangwaSession()
        s.userID = "u-abc"
        s.ct = "CT1"
        s.authType = .qq
        s.openID = "OID1"
        s.uin = 10001
        s.accessToken = "TOK1"
        s.tid = "TID1"
        return s
    }

    private func http200() -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://app.mval.qq.com/")!,
                        statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private func json(_ body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), http200())
    }

    // MARK: - Cookie 拼装（对齐 CookieHelper）

    @Test("QQ 登录：Cookie 拼装 + o 前缀 + ct 不进 Cookie")
    func qqCookieBuild() {
        let s = qqSession()
        let ck = s.cookieHeader

        #expect(ck.contains("clientType=9"))
        #expect(ck.contains("acctype=qc"))
        #expect(ck.contains("uin=o10001"))          // QQ 号必须带 o 前缀
        #expect(ck.contains("appid=102061775"))
        #expect(ck.contains("accountType=5"))
        #expect(ck.contains("userId=u-abc"))
        #expect(ck.contains("tid=TID1"))
        #expect(!ck.contains("CT1"))                // ct 只在 body 里出现
        #expect(s.accountType == 5)
        #expect(s.isQQ)
    }

    @Test("微信登录：appid / acctype 正确且不带 uin")
    func weChatCookieBuild() {
        var s = ZhangwaSession()
        s.userID = "u-abc"
        s.authType = .wechat
        s.openID = "OID2"
        s.accessToken = "TOK2"

        let ck = s.cookieHeader
        #expect(ck.contains("acctype=wx"))
        #expect(ck.contains("wxcbb49f1f39656c2a"))
        #expect(ck.contains("accountType=2"))
        #expect(!ck.contains("uin="))
        #expect(!s.isQQ)
    }

    // MARK: - Cookie 解析

    @Test("Cookie 解析：字段还原 + 零损耗回放")
    func cookieParse() {
        let raw = "clientType=9; acctype=qc; uin=o10001; appid=102061775; openid=OID; "
            + "access_token=TOK; userId=u-123; accountType=5; tid=TID"
        let s = ZhangwaSession.from(cookieHeader: raw)

        #expect(s.userID == "u-123")
        #expect(s.uin == 10001)
        #expect(s.accountType == 5)
        #expect(s.tid == "TID")
        #expect(s.openID == "OID")
        #expect(s.accessToken == "TOK")
        #expect(s.isValid)
        #expect(s.cookieHeader == raw)     // 原始串原样回放
    }

    @Test("Cookie 解析：微信")
    func weChatCookieParse() {
        let s = ZhangwaSession.from(cookieHeader: "clientType=9; acctype=wx; openid=O; userId=u-1")
        #expect(s.accountType == 2)
        #expect(s.authType == .wechat)
    }

    // MARK: - 域名重写（ValUrlTransformer）

    @Test("域名重写：mlol → mval，掌瓦域名不被二次改动")
    func hostRewrite() {
        let c = ZhangwaClient(session: ZhangwaSession())
        #expect(c.rewriteHost("https://mlol.qt.qq.com/go/x").hasPrefix("https://app.mval.qq.com"))
        #expect(c.rewriteHost("https://mlolpre.qt.qq.com/go/x").hasPrefix("https://apptest.mval.qq.com"))
        #expect(c.rewriteHost("/go/x") == "https://app.mval.qq.com/go/x")
        #expect(c.rewriteHost("https://app.mval.qq.com/go/x") == "https://app.mval.qq.com/go/x")
    }

    // MARK: - session json

    @Test("mval_session.json 解析（含 ct，可自刷新）")
    func sessionJSONParse() throws {
        let text = """
        {"t":"2026-01-01T00:00:00Z","kind":"SESSION","user_id":"u-9","ct":"CTX",
         "auth_type":4,"openid":"O","uin":10001,"access_token":"TOK","tid":"TID"}
        """
        let s = try ZhangwaSession.from(sessionJSON: Data(text.utf8))
        #expect(s.userID == "u-9")
        #expect(s.ct == "CTX")
        #expect(s.uin == 10001)
        #expect(s.accountType == 5)
        #expect(s.isValid)
    }

    // MARK: - 信封 / game_zone / 999999

    @Test("信封解析 + game_zone 注入（POST 进 body、GET 进 query）")
    func envelopeAndZoneInjection() async throws {
        let c = ZhangwaClient(session: qqSession())
        var seen: [URLRequest] = []
        c.transportOverride = { [self] req in
            seen.append(req)
            return json(#"{"result":0,"msg":"ok","data":{"items":[1,2]}}"#)
        }

        let data = try await c.request("/go/x", body: [:])
        let dict = try #require(data as? [String: Any])
        #expect((dict["items"] as? [Any])?.count == 2)
        #expect(seen.count == 1)

        let req = try #require(seen.first)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.absoluteString == "https://app.mval.qq.com/go/x")
        #expect(req.value(forHTTPHeaderField: "Cookie")?.contains("clientType=9") == true)

        let sentData = try #require(req.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: sentData) as? [String: Any])
        #expect(sent["game_zone"] as? String == "val")
        #expect(sent["source_game_zone"] as? String == "")

        _ = try await c.request("/go/y", body: nil)
        let getReq = try #require(seen.last)
        #expect(getReq.httpMethod == "GET")
        #expect(getReq.url?.query?.contains("game_zone=val") == true)
    }

    @Test("result=999999 会刷新 wt 并重试一次")
    func ticketInvalidTriggersRefresh() async throws {
        let c = ZhangwaClient(session: qqSession())
        var calls: [String] = []

        c.transportOverride = { [self] req in
            let path = req.url?.path ?? ""
            calls.append(path)

            if path.contains("get_web_ticket") {
                let attempts = calls.filter { $0.contains("get_web_ticket") }.count
                return attempts == 1
                    ? json(#"{"result":999999,"msg":"票据异常","data":null}"#)
                    : json(#"{"result":0,"msg":"ok","data":{"wt":"NEW_WT"}}"#)
            }
            if path.contains("refresh_client_ticket") {
                return json(#"{"result":0,"msg":"ok","data":{"ct_info":{"ct":"NEW_CT","wt":"NEW_WT"}}}"#)
            }
            let businessCalls = calls.filter { $0 == "/go/store" }.count
            return businessCalls == 1
                ? json(#"{"result":999999,"msg":"票据异常","data":null}"#)
                : json(#"{"result":0,"msg":"ok","data":{"ok":true}}"#)
        }

        let data = try await c.request("/go/store", body: [:])
        #expect((data as? [String: Any])?["ok"] as? Bool == true)
        #expect(calls.contains("/go/auth/get_web_ticket"))
        #expect(c.session.tid == "NEW_WT")
    }

    @Test("业务错误码原样透传")
    func apiErrorSurfacesCode() async {
        let c = ZhangwaClient(session: qqSession())
        c.transportOverride = { [self] _ in
            json(#"{"result":10001,"msg":"no auth","data":null}"#)
        }
        do {
            _ = try await c.request("/go/z", body: [:])
            Issue.record("应当抛 ZhangwaError")
        } catch let e as ZhangwaError {
            #expect(e.apiCode == 10001)
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    @Test("没配商店路径时给出可读提示")
    func shopNotConfigured() async {
        let c = ZhangwaClient(session: qqSession())
        c.shopPath = nil          // 现在默认指向每日商店，要显式清掉来测这个分支
        do {
            _ = try await c.fetchStore()
            Issue.record("应当抛 ZhangwaError")
        } catch let e as ZhangwaError {
            #expect(e.errorDescription?.contains("商店") == true)
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    // MARK: 真实数据（2026-10 抓包）

    /// 用真实抓包响应跑一遍 —— 这是最关键的一个测试。
    /// 夹具：POST /go/mlol_store/agame/user_store  body={}  的真实响应
    @Test("真实抓包响应能解析出每日商店的 4 件商品")
    func normalizeRealDailyStore() throws {
        let url = Bundle.module.url(forResource: "daily_store_real", withExtension: "json")
        let file = try #require(url, "找不到 Fixtures/daily_store_real.json")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        let root = try #require(raw as? [String: Any])

        let snap = StoreNormalizer.normalize(root)

        #expect(snap.key == "dailystore")
        #expect(snap.title == "每日商店")
        #expect(snap.items.count == 4)

        #expect(snap.items[0].name == "金角生辉 判官")
        #expect(snap.items[0].price == 1290)
        #expect(snap.items[0].qualityKey == "purple")
        #expect(snap.items[0].rarity == .purple)
        #expect(snap.items[0].iconURL?.absoluteString.hasSuffix("C8D3C3A4-49EB-6EE4-50CF-C1BF6CFD2A12.png") == true)
        #expect(snap.items[0].likeText == "3.1万人想要")
        #expect(snap.items[0].tips == "请前往游戏中购买！")

        #expect(snap.items[1].name == "荆刺链刃")
        #expect(snap.items[1].price == 3180)
        #expect(snap.items[1].rarity == .orange)

        #expect(snap.items[3].name == "ORA x 颗秒 狂徒")
        #expect(snap.items[3].rarity == .yellow)
        #expect(snap.items[3].likeText == "53万人想要")

        // 服务端直接给的剩余秒数和刷新时刻
        #expect(snap.remainingSeconds == 60433)
        #expect(snap.remaining == "16 小时 47 分")
        let expires = try #require(snap.expiresAt)
        #expect(abs(expires.timeIntervalSince1970 - 1792367999) < 1)

        #expect(snap.items[0].qualityText == "紫")
    }

    @Test("真实响应里同时有其他面板时，优先选 dailystore")
    func prefersDailyStorePanel() {
        let root: [String: Any] = [
            "result": 0,
            "data": [
                ["key": "kingdomstore", "title": "王国商店",
                 "list": [["goods_name": "独狼 称号", "rmb_price": "2500"]]],
                ["key": "dailystore", "title": "每日商店",
                 "list": [["goods_name": "金角生辉 判官", "rmb_price": "1290",
                           "quality": "purple"]]],
            ],
        ]
        let snap = StoreNormalizer.normalize(root)
        #expect(snap.key == "dailystore")
        #expect(snap.items.first?.name == "金角生辉 判官")
    }

    // MARK: - 商店归一化（通用形态）

    @Test("归一化：SkinsPanelLayout.SingleItemOffers 形态")
    func normalizeStore() throws {
        let raw: [String: Any] = [
            "SkinsPanelLayout": [
                "SingleItemOffers": [
                    ["OfferID": "o1", "Name": "侦察行动 幻影",
                     "weaponName": "幻影 / Phantom", "Cost": 1775,
                     "quality": "premium", "owned": false],
                    ["OfferID": "o2", "Name": "起源 暴徒",
                     "Cost": 2175, "quality": 4, "owned": true],
                ],
                "next_refresh": 1_800_000_000,
            ],
        ]
        let snap = StoreNormalizer.normalize(raw)

        #expect(snap.items.count == 2)
        #expect(snap.items[0].name == "侦察行动 幻影")
        #expect(snap.items[0].price == 1775)
        #expect(snap.items[0].rarity == .purple)     // premium → purple
        #expect(snap.items[1].rarity == .orange)     // 4 → orange
        #expect(snap.items[1].owned)
        #expect(snap.expiresAt != nil)
        #expect(snap.rawKeys.contains("SkinsPanelLayout"))
    }

    @Test("归一化：扁平 items + 数字品质")
    func normalizeStoreAlternateShape() {
        let raw: [String: Any] = [
            "items": [
                ["id": "a", "name": "离子圣芒 短剑", "price": 875, "tier": 1],
                ["id": "b", "name": "至尊龙炎 蝴蝶刀", "price": 4950, "quality": "ultra"],
            ],
        ]
        let snap = StoreNormalizer.normalize(raw)
        #expect(snap.items.count == 2)
        #expect(snap.items[0].rarity == .blue)      // 1 → blue
        #expect(snap.items[1].rarity == .yellow)    // ultra → yellow
    }

    @Test("图片 URL：协议相对补 https，显式 http 保留",
          arguments: [
            ("//cdn.example.com/a.png", "https://cdn.example.com/a.png"),
            ("http://down.qq.com/a.png", "http://down.qq.com/a.png"),
            ("https://mval.qpic.cn/x.png", "https://mval.qpic.cn/x.png"),
          ])
    func imageURLHandling(input: String, expected: String) throws {
        let snap = StoreNormalizer.normalize([
            "items": [["id": "1", "name": "x", "goods_pic": input]],
        ])
        let url = try #require(snap.items.first?.iconURL)
        #expect(url.absoluteString == expected)
    }

    @Test("品质：5 个颜色各归其位，认不出来返回 nil（不硬塞默认档）")
    func rarityAliases() {
        #expect(Rarity.from("blue") == .blue)
        #expect(Rarity.from("GREEN") == .green)
        #expect(Rarity.from("purple") == .purple)
        #expect(Rarity.from("orange") == .orange)
        #expect(Rarity.from("yellow") == .yellow)
        // 数字档位
        #expect(Rarity.from(3) == .purple)
        #expect(Rarity.from("5") == .yellow)
        // 国际服 / 老写法别名
        #expect(Rarity.from("premium") == .purple)
        #expect(Rarity.from("exclusive") == .orange)
        #expect(Rarity.from("ultra") == .yellow)
        // 认不出来就是 nil
        #expect(Rarity.from("garbage") == nil)
        #expect(Rarity.from(nil) == nil)
        #expect(Rarity.from("") == nil)
    }

    @Test("SsoAuthType 与 accountType 的映射（AppContext 同款）")
    func accountTypeMapping() {
        #expect(SsoAuthType.qq.accountType == 5)
        #expect(SsoAuthType.wechat.accountType == 2)
        #expect(SsoAuthType.wt.accountType == 1)
        #expect(SsoAuthType.tourist.accountType == 1)
        #expect(SsoAuthType(rawValue: 4) == .qq)
        #expect(SsoAuthType(rawValue: 255) == .tourist)
    }

    @Test("探测不能把返回空壳的接口当成命中")
    func probeRejectsEmptyPayload() async {
        let c = ZhangwaClient(session: qqSession())
        c.shopCandidates = ["/go/zone/v3/channel?zone=shop&disableAlgo=0"]
        c.transportOverride = { [self] _ in
            // 这个接口就是返回 result=0 + data:null —— 曾经把正确路径覆盖掉
            json(#"{"result":0,"msg":"success","data":null}"#)
        }
        let results = await c.probeShop()
        #expect(results.count == 1)
        #expect(results[0].ok == false, "result=0 但 data 是空的不该算命中")
        #expect(results[0].detail.contains("空"))
    }

    @Test("hasPayload 的判定")
    func hasPayloadRule() {
        #expect(ZhangwaClient.hasPayload(["a": 1]) == true)
        #expect(ZhangwaClient.hasPayload([1, 2]) == true)
        #expect(ZhangwaClient.hasPayload("x") == true)
        #expect(ZhangwaClient.hasPayload(NSNull()) == false)
        #expect(ZhangwaClient.hasPayload([String: Any]()) == false)
        #expect(ZhangwaClient.hasPayload([Any]()) == false)
        #expect(ZhangwaClient.hasPayload("") == false)
        #expect(ZhangwaClient.hasPayload(nil) == false)
    }

    @Test("商店默认路径就是实测出来的那个接口")
    func shopCandidateIsFromAPK() {
        let c = ZhangwaClient(session: qqSession())
        // 2026-10 抓包实测：POST /go/mlol_store/agame/user_store body={}
        // 返回 data[].key == "dailystore"，title == "每日商店"
        #expect(c.shopPath == "/go/mlol_store/agame/user_store")
        #expect(c.shopCandidates.first == "/go/mlol_store/agame/user_store")
        #expect(ZhangwaClient.dailyStorePath == "/go/mlol_store/agame/user_store")
        #expect(c.probeHosts.contains("app.val.qq.com"))
        #expect(c.probeHosts.contains("app.mval.qq.com"))
    }

    @Test("默认配置下 fetchStore 直接打每日商店接口")
    func fetchStoreUsesDailyStorePath() async throws {
        let c = ZhangwaClient(session: qqSession())
        var seen: [URLRequest] = []
        c.transportOverride = { [self] req in
            seen.append(req)
            return json(#"{"result":0,"msg":"","data":[{"key":"dailystore","title":"每日商店","time":10,"end_ts":1792367999,"list":[{"goods_name":"x","rmb_price":"100","quality":"blue"}]}]}"#)
        }

        let raw = try await c.fetchStore()
        let req = try #require(seen.first)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path == "/go/mlol_store/agame/user_store")

        let snap = StoreNormalizer.normalize(raw)
        #expect(snap.items.count == 1)
        #expect(snap.title == "每日商店")
    }

    @Test("探测会两台域名都试，命中就停")
    func probeTriesBothHosts() async {
        let c = ZhangwaClient(session: qqSession())
        c.shopCandidates = ["/go/zone/v3/channel?zone=shop&disableAlgo=0"]
        var hits: [String] = []

        c.transportOverride = { [self] req in
            let h = req.url?.host ?? "?"
            hits.append(h)
            // 第一台(app.mval) 404，第二台(app.val) 成功
            if h == ZhangwaClient.hostProd {
                return json(#"{"result":404,"msg":"not found","data":null}"#)
            }
            return json(#"{"result":0,"msg":"ok","data":{"channel":[1,2,3]}}"#)
        }

        let results = await c.probeShop()
        #expect(results.count == 1)
        #expect(results[0].ok)
        #expect(results[0].detail.contains("app.val.qq.com"))
        #expect(hits.contains(ZhangwaClient.hostProd))
        #expect(hits.contains(ZhangwaClient.hostVal))
    }

    // MARK: ct 滚动续期

    @Test("refresh_client_ticket 会拿到新 ct，并把 ctUpdatedAt 记上")
    func clientTicketRenewalRecordsTimestamp() async throws {
        var s0 = qqSession()
        s0.ctUpdatedAt = 0
        let c = ZhangwaClient(session: s0)
        #expect(c.needsClientTicketRenewal, "没记时间就该续")

        c.transportOverride = { [self] req in
            #expect(req.url?.path == "/go/auth/refresh_client_ticket")
            // 真实响应的结构（含 bind_info）
            return json(#"""
            {"result":0,"msg":"","data":{
              "ct_info":{"ct":"NEW_CT_LONG","wt":"NEW_WT","result":0,
                         "user_id":"JA-1","uin":2751275315,
                         "openid":"74193457a-b8d058817457ae26_10200",
                         "refresh_ct_span":604800,"refresh_wt_span":1800},
              "bind_info":[{"uin":"A44A6AA89A42ECA6909C2492C2193D14",
                            "openid":"A44A6AA89A42ECA6909C2492C2193D14",
                            "uuid":"JA-1"}]
            }}
            """#)
        }

        let ok = try await c.refreshClientTicket()
        #expect(ok)
        #expect(c.session.ct == "NEW_CT_LONG")
        #expect(c.session.tid == "NEW_WT")

        // ⚠️ 最关键的一条：Cookie 的 openid 必须来自 bind_info，
        //    不能是 ct_info.openid（那是掌瓦自己的 openid，写进去 Cookie 就废了）
        #expect(c.session.openID == "A44A6AA89A42ECA6909C2492C2193D14")
        #expect(c.session.openID != "74193457a-b8d058817457ae26_10200")
        #expect(c.session.cookieHeader.contains("openid=A44A6AA89A42ECA6909C2492C2193D14"))

        #expect(c.session.ctUpdatedAt > 0)
        #expect(!c.needsClientTicketRenewal, "刚续过就不该再续")
    }

    @Test("ct 快到 7 天才续")
    func ctRenewalTiming() {
        let now = Date().timeIntervalSince1970

        func needs(afterDays days: Double, ct: String = "CT") -> Bool {
            var s = qqSession()
            s.ct = ct
            s.ctUpdatedAt = now - days * 86_400
            return ZhangwaClient(session: s).needsClientTicketRenewal
        }

        #expect(!needs(afterDays: 0))     // 刚拿到
        #expect(!needs(afterDays: 5))     // 5 天，还没到
        #expect(needs(afterDays: 6.5))    // 进了续期窗口（7 天 - 1 天余量）
        #expect(needs(afterDays: 8))      // 已经过期

        // 没有 ct 就续不了 —— 不该被判成「该续」（续也续不动）
        #expect(!needs(afterDays: 8, ct: ""))

        // 但「有 ct 却没记时间」要判成该续（比如用户直接粘的 Cookie）
        var noStamp = qqSession()
        noStamp.ctUpdatedAt = 0
        #expect(ZhangwaClient(session: noStamp).needsClientTicketRenewal)
    }

    @Test("实测的有效期常量")
    func ticketLifetimes() {
        #expect(ZhangwaSession.ctLifetime == 604_800)   // 7 天
        #expect(ZhangwaSession.wtLifetime == 1_800)     // 30 分钟
    }

    // MARK: - 抓包导入

    @Test("从 ndjson 抓包日志里提取会话与接口清单")
    func captureImportFromNDJSON() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zw-capture-\(UUID().uuidString).log")
        let cookie = "clientType=9; acctype=qc; uin=o10001; appid=102061775; "
            + "openid=OID; access_token=TOK; userId=u-777; accountType=5; tid=TID9"
        let lines = [
            #"{"dir":"REQ","method":"POST","url":"https://app.mval.qq.com/go/account/mval_index_new","cookie":"\#(cookie)","body":"{\"game_zone\":\"val\"}"}"#,
            #"{"dir":"RESP","url":"https://app.mval.qq.com/go/account/mval_index_new","body":"{\"result\":0,\"msg\":\"success\",\"data\":{\"a\":1}}"}"#,
            #"{"dir":"REQ","method":"POST","url":"https://app.mval.qq.com/go/agame/store/storefront","cookie":"\#(cookie)","body":"{}"}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let s = try CaptureImporter.session(fromFileAt: url.path)
        #expect(s.userID == "u-777")
        #expect(s.uin == 10001)
        #expect(s.isValid)

        let eps = try CaptureImporter.endpoints(fromFileAt: url.path)
        #expect(eps.count == 2)
        #expect(eps.contains { $0.looksLikeStore })
    }

    @Test("从 mval_session.json 提取会话")
    func captureImportFromSessionFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zw-session-\(UUID().uuidString).json")
        let text = """
        {"kind":"SESSION","user_id":"u-42","ct":"CT42","auth_type":4,
         "openid":"O42","uin":10001,"access_token":"TOK42","tid":"TID42"}
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let s = try CaptureImporter.session(fromFileAt: url.path)
        #expect(s.userID == "u-42")
        #expect(s.ct == "CT42")
        #expect(s.tid == "TID42")
    }
}
