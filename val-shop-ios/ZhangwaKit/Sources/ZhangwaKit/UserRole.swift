import Foundation

// ============================================================================
//  当前登录用户的游戏角色
// ============================================================================
//
//  来源：`POST /go/account/getallgameroles`，body 是空 `{}`
//  （com/tencent/qtl/module_account/game_role/b/a.java:5，
//   它的 getProtocolBody() 就是 `new JsonObject().toString()`）
//
//  真实响应长这样（省略无关字段）：
//
//      data: {
//        accGameRoles: [ { accountId, openId, uuid, gameInfos: [ { gameId, gameName,
//                          roleInfo: [ { roleName, roleText, level, ... } ] } ] } ],
//        gameRoleNum:  [ { gameId, roleNum } ],
//        mainRoleList: [ { gameId, roleName, roleText, level, nick_id, areaName } ]
//      }
//
//  ⚠️ 有两个字面量陷阱：
//
//  1. **`gameId` 不是游戏 ID**，是**游戏标识**：
//        "agame" = 无畏契约（端游）
//        "codev" = 无畏契约手游
//     真正的「游戏 ID」（玩家名字）是 `roleName`，形如 `天天开心#26170`。
//     字段名起得太坑，第一次看很容易搞反。
//
//  2. **`nick_id` 是 snake_case**，同级的 roleName / roleText 却是 camelCase。
//     服务端就是这么混着发的，别自作聪明"统一命名"。
//
//  `mainRoleList` 是「主角色」—— 每个游戏一条，正好是我们要的。
//  用 `accGameRoles` 也行，但要自己遍历两层，没必要。
// ============================================================================

/// 一个游戏角色（玩家在某款游戏下的身份）
public struct UserRole: Codable, Sendable, Equatable, Hashable {

    /// 游戏标识：`agame`（无畏契约端游）/ `codev`（无畏契约手游）
    ///
    /// ⚠️ 这不是「游戏 ID」。见文件顶部的说明。
    public var gameID: String

    /// ★ **游戏 ID** —— 玩家名字，形如 `天天开心#26170`
    public var roleName: String

    /// 段位文本，形如 `铂金I`。可能是空串。
    public var roleText: String

    /// 等级
    public var level: Int

    /// 名字后面的数字标签，形如 `26170`。可能为空。
    public var nickID: String

    /// 大区，形如 `正式服大区`
    public var areaName: String

    /// 游戏内角色 ID（UUID 形态），形如 `12c52a27-3599-5c92-...`
    public var gameRoleID: String

    /// 玩家卡面图片。可能为空。
    public var icon: String

    public init(gameID: String, roleName: String, roleText: String = "",
                level: Int = 0, nickID: String = "", areaName: String = "",
                gameRoleID: String = "", icon: String = "") {
        self.gameID = gameID
        self.roleName = roleName
        self.roleText = roleText
        self.level = level
        self.nickID = nickID
        self.areaName = areaName
        self.gameRoleID = gameRoleID
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "gameId"
        case roleName, roleText, level, areaName, icon
        // 服务端这里偏偏是 snake_case，和同级字段不一致
        case nickID = "nick_id"
        case gameRoleID = "game_role_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 全部走「取不到就给默认值」—— 这是展示用的数据，
        // 少一个字段不该让整个登录态解析失败
        gameID     = (try? c.decode(String.self, forKey: .gameID)) ?? ""
        roleName   = (try? c.decode(String.self, forKey: .roleName)) ?? ""
        roleText   = (try? c.decode(String.self, forKey: .roleText)) ?? ""
        level      = (try? c.decode(Int.self, forKey: .level)) ?? 0
        nickID     = (try? c.decode(String.self, forKey: .nickID)) ?? ""
        areaName   = (try? c.decode(String.self, forKey: .areaName)) ?? ""
        gameRoleID = (try? c.decode(String.self, forKey: .gameRoleID)) ?? ""
        icon       = (try? c.decode(String.self, forKey: .icon)) ?? ""
    }

    /// 展示用的名字。没有 roleName 时退回 gameRoleID，再不行给个占位。
    public var displayName: String {
        if !roleName.isEmpty { return roleName }
        if !nickID.isEmpty { return nickID }
        return "未知角色"
    }

    /// 「端游」还是「手游」
    public var platformText: String {
        switch gameID {
        case "agame": return "端游"
        case "codev": return "手游"
        default:      return gameID
        }
    }

    /// 是否是我们关心的那款（端游无畏契约 —— 每日商店就是它的）
    public var isValorantPC: Bool { gameID == "agame" }
}

/// `/go/account/getallgameroles` 的 `data`
public struct GameRoles: Codable, Sendable, Equatable {

    /// 主角色列表 —— 每个游戏一条。我们只用这个。
    public var mainRoleList: [UserRole]

    public init(mainRoleList: [UserRole] = []) {
        self.mainRoleList = mainRoleList
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mainRoleList = (try? c.decode([UserRole].self, forKey: .mainRoleList)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case mainRoleList
    }

    /// 挑出要展示的角色。
    ///
    /// 优先端游（`agame`）—— 这个 App 就是看端游每日商店的；
    /// 没有端游角色时才退而求其次取第一个，总比显示不出来强。
    public var preferred: UserRole? {
        mainRoleList.first(where: \.isValorantPC) ?? mainRoleList.first
    }

    public var isEmpty: Bool { mainRoleList.isEmpty }
}
