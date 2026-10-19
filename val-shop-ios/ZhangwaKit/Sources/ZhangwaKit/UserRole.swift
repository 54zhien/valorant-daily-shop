import Foundation

// ============================================================================
//  当前登录用户的游戏角色
// ============================================================================
//
//  来源：`POST /go/account/getallgameroles`，body 是空 `{}`
//  （com/tencent/qtl/module_account/game_role/b/a.java:5，
//   它的 getProtocolBody() 就是 `new JsonObject().toString()`）
//
//  三层结构：
//
//      data: {
//        accGameRoles: [               // 按**绑定账号**分组（QQ / 微信 各一个）
//          { accountId, accountType, openId, thirdType, uuid,
//            gameInfos: [
//              { gameId, gameName, gameIcon, gameRoleNum,
//                roleInfo: [           // ★ 该游戏下的**所有角色**（大号/小号）
//                  { roleName, roleText, fullTierText, level,
//                    nick_id, game_role_id, areaName, icon, ... }
//                ] }
//            ] }
//        ],
//        mainRoleList: [ ... ],        // 服务端标出来的「主角色」，每游戏一条
//        gameRoleNum:  [ { gameId, roleNum } ]
//      }
//
//  ⚠️ 三个字面量陷阱（都是实测撞出来的，不是猜的）：
//
//  1. **`gameId` 不是游戏 ID**，是**游戏标识**：
//        "agame" = 无畏契约（端游）
//        "codev" = 无畏契约手游
//     真正的「游戏 ID」（玩家名字）是 `roleName`，形如 `天天开心#26170`。
//     字段名起得太坑，而且 MainRoleInfo.getGameId() 看起来特别像答案。
//
//  2. **`nick_id` 是 snake_case**，同级的 roleName / roleText 却是 camelCase。
//     服务端就是这么混着发的，别自作聪明"统一命名"。
//
//  3. **`gameName` 不在 roleInfo 里**，在上一层的 gameInfos 上。
//     所以要拍平的时候顺手带下来，否则角色列表里认不出是哪个游戏的。
// ============================================================================

/// 一个游戏角色（玩家在某款游戏下的身份）
public struct UserRole: Codable, Sendable, Equatable, Hashable {

    /// 游戏标识：`agame`（无畏契约端游）/ `codev`（无畏契约手游）
    ///
    /// ⚠️ 这不是「游戏 ID」。见文件顶部的说明。
    public var gameID: String

    /// ★ **游戏 ID** —— 玩家名字，形如 `天天开心#26170`
    public var roleName: String

    /// 段位短文本，形如 `铂金I`。可能是空串。
    public var roleText: String

    /// 更完整的段位文本。服务端同时给 roleText 和 fullTierText，
    /// 通常一样，但段位体系复杂时后者更准 —— 展示优先用它。
    public var fullTierText: String

    /// 段位数值。现在只是存着，将来做段位图标会用到。
    public var tierID: Int

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

    /// 所属游戏名，形如 `无畏契约`。
    ///
    /// `roleInfo` 里的条目本身**不带**这个（在上一层的 gameInfos 上），
    /// 拍平时顺手带下来 —— 角色列表里得能看出是哪个游戏的。
    public var gameName: String

    public init(gameID: String, roleName: String, roleText: String = "",
                level: Int = 0, nickID: String = "", areaName: String = "",
                gameRoleID: String = "", icon: String = "", gameName: String = "",
                fullTierText: String = "", tierID: Int = 0) {
        self.gameID = gameID
        self.roleName = roleName
        self.roleText = roleText
        self.level = level
        self.nickID = nickID
        self.areaName = areaName
        self.gameRoleID = gameRoleID
        self.icon = icon
        self.gameName = gameName
        self.fullTierText = fullTierText
        self.tierID = tierID
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "gameId"
        case roleName, roleText, level, areaName, icon
        // 服务端这里偏偏是 snake_case，和同级字段不一致
        case nickID = "nick_id"
        case gameRoleID = "game_role_id"
        case fullTierText
        case tierID = "tier_id"
        // 这个不在 JSON 里，是拍平时补的；写进 CodingKeys 只是为了完整
        case gameName
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 全部走「取不到就给默认值」—— 这是展示用的数据，
        // 少一个字段不该让整块登录态解析失败
        gameID       = (try? c.decode(String.self, forKey: .gameID)) ?? ""
        roleName     = (try? c.decode(String.self, forKey: .roleName)) ?? ""
        roleText     = (try? c.decode(String.self, forKey: .roleText)) ?? ""
        fullTierText = (try? c.decode(String.self, forKey: .fullTierText)) ?? ""
        tierID       = (try? c.decode(Int.self, forKey: .tierID)) ?? 0
        level        = (try? c.decode(Int.self, forKey: .level)) ?? 0
        nickID       = (try? c.decode(String.self, forKey: .nickID)) ?? ""
        areaName     = (try? c.decode(String.self, forKey: .areaName)) ?? ""
        gameRoleID   = (try? c.decode(String.self, forKey: .gameRoleID)) ?? ""
        icon         = (try? c.decode(String.self, forKey: .icon)) ?? ""
        gameName     = (try? c.decode(String.self, forKey: .gameName)) ?? ""
    }

    /// 唯一标识，用来记住「用户选了哪个角色」+ 去重。
    ///
    /// 优先用服务端给的 game_role_id（UUID，最稳）；
    /// 缺了时退回 gameID + roleName 的组合。
    public var identityKey: String {
        if !gameRoleID.isEmpty { return gameRoleID }
        if !roleName.isEmpty { return "\(gameID)|\(roleName)" }
        return "\(gameID)|\(nickID)|unknown"
    }

    /// 展示用的名字。没有 roleName 时退回 nickID，再不行给个占位。
    public var displayName: String {
        if !roleName.isEmpty { return roleName }
        if !nickID.isEmpty { return nickID }
        return "未知角色"
    }

    /// 展示用的段位文本。fullTierText 更准，为空时退回 roleText。
    public var rankText: String {
        if !fullTierText.isEmpty { return fullTierText }
        return roleText
    }

    /// 「端游」还是「手游」
    public var platformText: String {
        switch gameID {
        case "agame": return "端游"
        case "codev": return "手游"
        default:      return gameID.isEmpty ? "未知" : gameID
        }
    }

    /// 是否是我们关心的那款（端游无畏契约 —— 每日商店就是它的）
    public var isValorantPC: Bool { gameID == "agame" }
}

// MARK: - 账号 / 游戏 / 总表

/// 一个绑定到掌瓦账号的第三方账号（QQ / 微信）
public struct BoundAccount: Codable, Sendable, Equatable {
    public var accountId: String
    public var openId: String
    /// 5 = QQ，2 = 微信（和 Cookie 里的 accountType 对应）
    public var thirdType: Int
    /// 掌瓦自己的账号 ID，和 `session.userID` 是同一个东西
    public var uuid: String
    public var gameInfos: [GameInfo]

    public init(accountId: String = "", openId: String = "", thirdType: Int = 0,
                uuid: String = "", gameInfos: [GameInfo] = []) {
        self.accountId = accountId
        self.openId = openId
        self.thirdType = thirdType
        self.uuid = uuid
        self.gameInfos = gameInfos
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = (try? c.decode(String.self, forKey: .accountId)) ?? ""
        openId    = (try? c.decode(String.self, forKey: .openId)) ?? ""
        thirdType = (try? c.decode(Int.self, forKey: .thirdType)) ?? 0
        uuid      = (try? c.decode(String.self, forKey: .uuid)) ?? ""
        gameInfos = (try? c.decode([GameInfo].self, forKey: .gameInfos)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case accountId, openId, thirdType, uuid, gameInfos
    }

    /// 是当前登录用的那个账号吗
    public func isCurrent(userID: String) -> Bool {
        !uuid.isEmpty && uuid == userID
    }

    /// 这个绑定账号的登录方式
    public var platformText: String {
        switch thirdType {
        case 5:  return "QQ"
        case 2:  return "微信"
        default: return "账号 \(thirdType)"
        }
    }
}

/// 一个游戏（无畏契约 / 无畏契约手游）
public struct GameInfo: Codable, Sendable, Equatable {
    /// 游戏标识：`agame` / `codev`（⚠️ 不是游戏 ID）
    public var gameId: String
    public var gameName: String
    public var gameIcon: String
    public var gameRoleNum: Int
    public var roleInfo: [UserRole]

    public init(gameId: String = "", gameName: String = "", gameIcon: String = "",
                gameRoleNum: Int = 0, roleInfo: [UserRole] = []) {
        self.gameId = gameId
        self.gameName = gameName
        self.gameIcon = gameIcon
        self.gameRoleNum = gameRoleNum
        self.roleInfo = roleInfo
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameId      = (try? c.decode(String.self, forKey: .gameId)) ?? ""
        gameName    = (try? c.decode(String.self, forKey: .gameName)) ?? ""
        gameIcon    = (try? c.decode(String.self, forKey: .gameIcon)) ?? ""
        gameRoleNum = (try? c.decode(Int.self, forKey: .gameRoleNum)) ?? 0
        roleInfo    = (try? c.decode([UserRole].self, forKey: .roleInfo)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case gameId, gameName, gameIcon, gameRoleNum, roleInfo
    }

    /// 是不是端游无畏契约
    public var isValorantPC: Bool { gameId == "agame" }
}

/// `/go/account/getallgameroles` 的 `data`
public struct GameRoles: Codable, Sendable, Equatable {

    /// 主角色列表 —— 每个游戏一条（服务端已经挑好了）
    public var mainRoleList: [UserRole]

    /// 全部角色，按账号 / 游戏分组
    public var accGameRoles: [BoundAccount]

    public init(mainRoleList: [UserRole] = [], accGameRoles: [BoundAccount] = []) {
        self.mainRoleList = mainRoleList
        self.accGameRoles = accGameRoles
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mainRoleList = (try? c.decode([UserRole].self, forKey: .mainRoleList)) ?? []
        accGameRoles = (try? c.decode([BoundAccount].self, forKey: .accGameRoles)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case mainRoleList, accGameRoles
    }

    /// 拍平出来的全部角色
    ///
    /// ⚠️ 这里要**从父层补两个字段**：`accGameRoles[].gameInfos[].roleInfo[]`
    /// 里的条目既没有 `gameId` 也没有 `gameName` —— 两个都在上一层的
    /// `gameInfos` 条目上。不补的话 `gameID` 会是空串，
    /// `isValorantPC` 全判 false，结果就是**展示错角色**
    /// （会退到 `allRoles.first`，可能拿到手游那个）。
    ///
    /// 这个坑是测试抓出来的：先用 mainRoleList 那条路测过没问题，
    /// 加上 accGameRoles 之后才暴露。
    ///
    /// 同一角色可能在 mainRoleList 和 accGameRoles 里各出现一次，
    /// 按 `identityKey` 去重。
    public var allRoles: [UserRole] {
        var seen = Set<String>()
        var out: [UserRole] = []

        func add(_ r: UserRole, gameId: String, gameName: String) {
            var copy = r
            // 父层优先，子层自带时也不覆盖（将来服务端补上就自动生效）
            if copy.gameID.isEmpty { copy.gameID = gameId }
            if copy.gameName.isEmpty { copy.gameName = gameName }
            let key = copy.identityKey
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(copy)
        }

        for acc in accGameRoles {
            for g in acc.gameInfos {
                for r in g.roleInfo { add(r, gameId: g.gameId, gameName: g.gameName) }
            }
        }
        // mainRoleList 作为补充（它自己带 gameId）
        for r in mainRoleList { add(r, gameId: "", gameName: "") }

        return out
    }

    /// 能切换的角色 —— 只挑端游的。
    ///
    /// 为什么不把 `codev`（手游）也放进来：这个 App 看的是端游每日商店，
    /// 切到手游角色只会让人以为商店数据会跟着变，其实不会。
    public var selectableRoles: [UserRole] {
        let pc = allRoles.filter(\.isValorantPC)
        return pc.isEmpty ? allRoles : pc
    }

    /// 挑默认展示的角色：优先端游 → 退 mainRoleList 第一个 → 退全部第一个
    public var preferred: UserRole? {
        allRoles.first(where: \.isValorantPC)
            ?? mainRoleList.first
            ?? allRoles.first
    }

    /// 没有任何角色可展示。
    ///
    /// 判据是 `allRoles` 而不是「数组空不空」——
    /// 服务端可能返回一个 `accGameRoles` 里有元素、但 `roleInfo` 为空的账号
    /// （绑定过但没建角色），那种情况对 UI 来说同样是「没东西可显示」。
    public var isEmpty: Bool { allRoles.isEmpty }
}
