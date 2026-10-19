import Foundation
import Testing

@testable import ZhangwaKit

// ============================================================================
//  游戏角色解析
// ============================================================================
//
//  夹具是**从服务器真实响应裁出来的**（只去掉无关字段），
//  不是手写的 —— 手写的夹具会让测试跟着代码一起错，
//  这个项目已经在 ct_info/login_info 那次栽过一次了。
// ============================================================================

@Suite("游戏角色")
struct UserRoleTests {

    @Test("解析真实响应 —— gameId 是游戏标识，roleName 才是游戏 ID")
    func parsesRealResponse() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))

        #expect(roles.mainRoleList.count == 2)

        let pc = roles.mainRoleList[0]
        #expect(pc.gameID == "agame")                  // ★ 是游戏标识，不是游戏 ID
        #expect(pc.roleName == "天天开心#26170")        // ★ 这才是游戏 ID
        #expect(pc.roleText == "铂金I")
        #expect(pc.level == 254)
        #expect(pc.nickID == "26170")                  // snake_case 的 nick_id 要能取到
        #expect(pc.areaName == "正式服大区")
        #expect(pc.platformText == "端游")
        #expect(pc.isValorantPC)

        let mobile = roles.mainRoleList[1]
        #expect(mobile.gameID == "codev")
        #expect(mobile.roleName == "不能悲")
        #expect(mobile.platformText == "手游")
        #expect(!mobile.isValorantPC)
    }

    @Test("优先选端游角色（每日商店就是端游的）")
    func prefersPCRole() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let pick = try #require(roles.preferred)
        #expect(pick.gameID == "agame")
        #expect(pick.roleName == "天天开心#26170")
    }

    @Test("只有手游角色时退回第一个，不能什么都不显示")
    func fallsBackToFirst() throws {
        let json = """
        {"mainRoleList":[{"gameId":"codev","roleName":"不能悲","roleText":"白银II","level":36}]}
        """
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(json.utf8))
        let pick = try #require(roles.preferred)
        #expect(pick.gameID == "codev")
        #expect(pick.roleName == "不能悲")
    }

    @Test("字段缺失不能炸 —— 少一个字段不该让整块登录态解析失败")
    func toleratesMissingFields() throws {
        // 只有 roleName，其它什么都没有
        let json = #"{"mainRoleList":[{"roleName":"孤儿玩家#1"}]}"#
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(json.utf8))
        let r = try #require(roles.preferred)
        #expect(r.roleName == "孤儿玩家#1")
        #expect(r.gameID.isEmpty)
        #expect(r.level == 0)
        #expect(r.roleText.isEmpty)
        // 空段位不该显示成 "nil" 之类的东西
        #expect(r.displayName == "孤儿玩家#1")
    }

    @Test("连 roleName 都没有时用兜底名，不能显示空")
    func displayNameNeverEmpty() {
        let r = UserRole(gameID: "agame", roleName: "", nickID: "26170")
        #expect(r.displayName == "26170")

        let r2 = UserRole(gameID: "agame", roleName: "")
        #expect(r2.displayName == "未知角色")
        #expect(!r2.displayName.isEmpty)
    }

    @Test("空响应 / 结构完全不对 —— 要返回空对象而不是抛错")
    func emptyAndMalformed() throws {
        // 服务端返回了 data 但没有 mainRoleList
        let a = try JSONDecoder().decode(GameRoles.self, from: Data("{}".utf8))
        #expect(a.isEmpty)
        #expect(a.preferred == nil)

        // mainRoleList 是空数组
        let b = try JSONDecoder().decode(GameRoles.self,
                                         from: Data(#"{"mainRoleList":[]}"#.utf8))
        #expect(b.isEmpty)
        #expect(b.preferred == nil)

        // mainRoleList 类型不对（服务端改结构时）
        let c = try JSONDecoder().decode(GameRoles.self,
                                         from: Data(#"{"mainRoleList":"oops"}"#.utf8))
        #expect(c.isEmpty)
    }

    /// 从服务器真实响应裁出来的（2025-10 实测）
    static let real = """
    {"mainRoleList":[
      {"roleId":"天天开心","roleName":"天天开心#26170","areaId":1,
       "areaName":"正式服大区","level":254,"roleText":"铂金I","fullTierText":"铂金I",
       "tier_id":15,"visible":1,"game_open_id":"3060806288901451405",
       "game_role_id":"12c52a27-3599-5c92-a308-0bb4195246ec",
       "icon":"https://game.gtimg.cn/images/val/agamezlk/PlayerCards/A372C539.png",
       "nick_id":"26170","content":"天天开心|正式服大区|Lv254","gameId":"agame"},
      {"roleId":"不能悲","roleName":"不能悲","areaId":1,"areaName":"正式服大区",
       "level":36,"roleText":"白银II","tier_id":8,"visible":1,
       "game_role_id":"0dfd0d29-6ec9-5bb7-897e-3099e4959595",
       "nick_id":"","content":"不能悲|正式服大区|Lv36","gameId":"codev"}
    ]}
    """
}
