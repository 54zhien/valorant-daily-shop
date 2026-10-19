import Foundation
import Testing

@testable import ZhangwaKit

// ============================================================================
//  游戏角色解析
// ============================================================================
//
//  夹具是**从服务器真实响应裁出来的**（只去掉无关字段，结构原样保留），
//  不是手写的 —— 手写的夹具会让测试跟着代码一起错。
//  这个项目已经在 ct_info / login_info 那次栽过一次了。
// ============================================================================

@Suite("游戏角色")
struct UserRoleTests {

    // MARK: 关键陷阱

    @Test("gameId 是游戏标识，roleName 才是游戏 ID")
    func gameIDIsNotTheGameID() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let r = try #require(roles.preferred)

        // ★ 这两个断言就是在钉死那个字段名陷阱：
        //   gameID 是 "agame"（游戏标识），名字是 roleName
        #expect(r.gameID == "agame")
        #expect(r.roleName == "天天开心#26170")
        #expect(r.displayName == "天天开心#26170")
        // 如果哪天有人「顺手」把 displayName 改成返回 gameID，
        // 这条会立刻炸 —— 而那是必然的误用
        #expect(r.displayName != r.gameID)
    }

    @Test("nick_id 是 snake_case，要能取到")
    func snakeCaseNickID() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let r = try #require(roles.preferred)
        #expect(r.nickID == "26170")
    }

    @Test("gameName 不在 roleInfo 里 —— 拍平时要从上一层带下来")
    func gameNameCarriedDown() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let all = roles.allRoles
        let pc = try #require(all.first { $0.gameID == "agame" })
        // roleInfo 条目本身没有 gameName，必须由 allRoles 补上
        #expect(pc.gameName == "无畏契约")

        let mobile = try #require(all.first { $0.gameID == "codev" })
        #expect(mobile.gameName == "无畏契约手游")
    }

    // MARK: 解析

    @Test("解析真实响应")
    func parsesRealResponse() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))

        #expect(roles.mainRoleList.count == 2)
        #expect(roles.accGameRoles.count == 1)          // 只绑了一个账号
        #expect(roles.accGameRoles[0].gameInfos.count == 2)
        #expect(!roles.isEmpty)

        let r = roles.mainRoleList[0]
        #expect(r.roleText == "铂金I")
        #expect(r.fullTierText == "铂金I")
        #expect(r.rankText == "铂金I")
        #expect(r.level == 254)
        #expect(r.areaName == "正式服大区")
        #expect(r.tierID == 15)
        #expect(r.gameRoleID == "12c52a27-3599-5c92-a308-0bb4195246ec")
        #expect(r.icon.contains("PlayerCards"))
        #expect(r.platformText == "端游")
        #expect(r.isValorantPC)
    }

    @Test("rankText 优先用 fullTierText")
    func rankTextPrefersFull() {
        // 两者不同时（段位体系复杂的情况）要选 fullTierText
        let a = UserRole(gameID: "agame", roleName: "A", roleText: "铂金",
                         fullTierText: "铂金I")
        #expect(a.rankText == "铂金I")

        // fullTierText 为空时退回 roleText
        let b = UserRole(gameID: "agame", roleName: "B", roleText: "白银II")
        #expect(b.rankText == "白银II")

        // 两个都空不能崩
        let c = UserRole(gameID: "agame", roleName: "C")
        #expect(c.rankText.isEmpty)
    }

    // MARK: 拍平与去重

    @Test("allRoles 拍平两层结构，并按 identityKey 去重")
    func flattensAndDedups() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let all = roles.allRoles

        // accGameRoles 里有 2 个（agame 1 + codev 1），
        // mainRoleList 里那 2 个是重复的，应该被去重掉
        #expect(all.count == 2)
        #expect(Set(all.map(\.identityKey)).count == 2)   // 确实没重复
        #expect(all.contains { $0.gameID == "agame" })
        #expect(all.contains { $0.gameID == "codev" })
    }

    @Test("缺 game_role_id 时 identityKey 退回 gameID+roleName")
    func identityKeyFallback() {
        let a = UserRole(gameID: "agame", roleName: "天天开心#26170")
        #expect(a.identityKey == "agame|天天开心#26170")

        // 两个都没带 game_role_id 但名字不同的角色不能算同一个
        let b = UserRole(gameID: "agame", roleName: "小号#1")
        #expect(a.identityKey != b.identityKey)

        // 完全没名字也得有个稳定的 key
        let c = UserRole(gameID: "agame", roleName: "", nickID: "999")
        #expect(c.identityKey == "agame|999|unknown")
    }

    // MARK: 选择

    @Test("selectableRoles 只给端游角色（切手游会让人以为商店会变）")
    func selectableRolesPCOnly() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let sel = roles.selectableRoles
        #expect(sel.count == 1)
        // 注意：不能在 #expect 里直接写 allSatisfy —— 它是 rethrows，
        // 宏会把表达式包进闭包，于是编译器要求 try。先算出来再断言。
        let allArePC = sel.allSatisfy(\.isValorantPC)
        #expect(allArePC)
        #expect(sel[0].roleName == "天天开心#26170")
    }

    @Test("只有手游角色时 selectableRoles 退回全部，不能给空的")
    func selectableFallsBackWhenNoPC() throws {
        let json = """
        {"accGameRoles":[{"gameInfos":[{"gameId":"codev","gameName":"无畏契约手游",
          "roleInfo":[{"roleName":"不能悲","gameId":"codev"}]}]}]}
        """
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(json.utf8))
        #expect(roles.selectableRoles.count == 1)
        #expect(roles.selectableRoles[0].roleName == "不能悲")
    }

    @Test("优先选端游角色")
    func prefersPCRole() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let pick = try #require(roles.preferred)
        #expect(pick.gameID == "agame")
    }

    @Test("多角色时全部能列出来（给切换用）")
    func multipleRolesListed() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.twoRoles.utf8))
        let sel = roles.selectableRoles
        #expect(sel.count == 2)
        #expect(sel.map(\.roleName) == ["大号#11111", "小号#22222"])
        #expect(sel[0].identityKey != sel[1].identityKey)
    }

    // MARK: 健壮性

    @Test("字段缺失不能炸 —— 少一个字段不该让整块登录态解析失败")
    func toleratesMissingFields() throws {
        let json = #"{"mainRoleList":[{"roleName":"孤儿玩家#1"}]}"#
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(json.utf8))
        let r = try #require(roles.preferred)
        #expect(r.roleName == "孤儿玩家#1")
        #expect(r.gameID.isEmpty)
        #expect(r.level == 0)
        #expect(r.rankText.isEmpty)
        #expect(r.displayName == "孤儿玩家#1")
        #expect(r.platformText == "未知")
    }

    @Test("连 roleName 都没有时用兜底名，不能显示空")
    func displayNameNeverEmpty() {
        #expect(UserRole(gameID: "agame", roleName: "", nickID: "26170")
                    .displayName == "26170")
        #expect(UserRole(gameID: "agame", roleName: "").displayName == "未知角色")
    }

    @Test("空响应 / 结构不对 —— 返回空对象而不是抛错")
    func emptyAndMalformed() throws {
        for json in [#"{}"#, #"{"mainRoleList":[]}"#,
                     #"{"mainRoleList":"oops"}"#,
                     #"{"accGameRoles":null}"#,
                     #"{"accGameRoles":[{"gameInfos":"nope"}]}"#] {
            let g = try JSONDecoder().decode(GameRoles.self, from: Data(json.utf8))
            #expect(g.isEmpty)
            #expect(g.preferred == nil)
            #expect(g.allRoles.isEmpty)
            #expect(g.selectableRoles.isEmpty)
        }
    }

    @Test("绑定账号能标出是不是当前登录的那个")
    func boundAccountIsCurrent() throws {
        let roles = try JSONDecoder().decode(GameRoles.self, from: Data(Self.real.utf8))
        let acc = roles.accGameRoles[0]
        #expect(acc.thirdType == 5)                       // QQ
        #expect(acc.platformText == "QQ")
        #expect(acc.isCurrent(userID: "JA-3095d6174193457a-b8d058817457ae26"))
        #expect(!acc.isCurrent(userID: "别的账号"))
        // uuid 为空时不该误判成"当前账号"
        #expect(!BoundAccount().isCurrent(userID: ""))
    }

    // MARK: 夹具（从真实响应裁出来）

    /// 2025-10 实测响应。结构和字段名原样保留。
    static let real = """
    {
      "accGameRoles": [{
        "accountId": "A44A6AA89A42ECA6909C2492C2193D14",
        "accountType": 5,
        "openId": "A44A6AA89A42ECA6909C2492C2193D14",
        "thirdType": 5,
        "uuid": "JA-3095d6174193457a-b8d058817457ae26",
        "gameInfos": [
          {
            "gameId": "agame", "gameName": "无畏契约",
            "gameIcon": "https://game.gtimg.cn/images/val/agamezlk/agame.png",
            "game_icon2": "https://down.qq.com/lolapp/app/friend_val.png",
            "gameRoleNum": 1,
            "roleInfo": [{
              "roleId": "天天开心", "roleType": 1, "roleName": "天天开心#26170",
              "areaId": 1, "areaName": "正式服大区", "level": 254,
              "roleText": "铂金I", "fullTierText": "铂金I", "tier_id": 15,
              "visible": 1, "game_open_id": "3060806288901451405",
              "game_role_id": "12c52a27-3599-5c92-a308-0bb4195246ec",
              "icon": "https://game.gtimg.cn/images/val/agamezlk/PlayerCards/A372C539.png",
              "nick_id": "26170", "content": "天天开心|正式服大区|Lv254"
            }]
          },
          {
            "gameId": "codev", "gameName": "无畏契约手游",
            "gameIcon": "", "gameRoleNum": 1,
            "roleInfo": [{
              "roleId": "不能悲", "roleType": 1, "roleName": "不能悲",
              "areaId": 1, "areaName": "正式服大区", "level": 36,
              "roleText": "白银II", "fullTierText": "白银II", "tier_id": 8,
              "visible": 1, "game_role_id": "0dfd0d29-6ec9-5bb7-897e-3099e4959595",
              "icon": "", "nick_id": "", "content": "不能悲|正式服大区|Lv36"
            }]
          }
        ]
      }],
      "gameRoleNum": [{"gameId": "agame", "roleNum": 1}, {"gameId": "codev", "roleNum": 1}],
      "mainRoleList": [
        {"roleId": "天天开心", "roleName": "天天开心#26170", "areaId": 1,
         "areaName": "正式服大区", "level": 254, "roleText": "铂金I",
         "fullTierText": "铂金I", "tier_id": 15, "visible": 1,
         "game_role_id": "12c52a27-3599-5c92-a308-0bb4195246ec",
         "icon": "https://game.gtimg.cn/images/val/agamezlk/PlayerCards/A372C539.png",
         "nick_id": "26170", "gameId": "agame"},
        {"roleId": "不能悲", "roleName": "不能悲", "areaId": 1,
         "areaName": "正式服大区", "level": 36, "roleText": "白银II",
         "fullTierText": "白银II", "tier_id": 8, "visible": 1,
         "game_role_id": "0dfd0d29-6ec9-5bb7-897e-3099e4959595",
         "nick_id": "", "gameId": "codev"}
      ]
    }
    """

    /// 一个账号下有两个端游角色（用来验证切换列表）
    static let twoRoles = """
    {
      "accGameRoles": [{"thirdType": 5, "uuid": "JA-x", "gameInfos": [{
        "gameId": "agame", "gameName": "无畏契约", "gameRoleNum": 2,
        "roleInfo": [
          {"roleName": "大号#11111", "gameId": "agame", "level": 254,
           "game_role_id": "r-1", "roleText": "铂金I"},
          {"roleName": "小号#22222", "gameId": "agame", "level": 30,
           "game_role_id": "r-2", "roleText": "白银II"}
        ]}]}],
      "mainRoleList": []
    }
    """
}
