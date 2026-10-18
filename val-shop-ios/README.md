# 无畏契约 · 每日商店（iOS 26 / Liquid Glass）

原生 SwiftUI 的独立每日商店 App。**代码推 GitHub → Actions 出未签名 IPA → 手机上自签安装。**

技术栈按 Apple 2025–2026 最新要求：**iOS 26 部署目标 + Liquid Glass 全家桶 + Swift 6 严格并发 + Observation + Swift Testing**。

```
val-shop-ios/
├─ .github/workflows/ios.yml      ← 在仓库根的 .github/ 下，见下方目录说明
├─ ZhangwaKit/                    ✅ 已验证：swift test 17/17 通过，零警告
│   ├─ Package.swift              swift-tools-version 6.0，Swift 6 语言模式
│   ├─ Sources/ZhangwaKit/        协议层（Sendable 模型 + @MainActor client）
│   └─ Tests/ZhangwaKitTests/     Swift Testing（@Suite / @Test / #expect）
├─ App/                           ⚠️ 需在 Xcode 26 上编译（本机无 SwiftUI）
│   ├─ ZhangwaShopApp.swift       @main + TabView + tabBarMinimizeBehavior
│   ├─ LiquidGlass.swift          ★ 全项目唯一直接调 iOS 26 玻璃 API 的文件
│   ├─ AppModel.swift             @Observable + @MainActor
│   ├─ ShopView.swift             玻璃卡片网格 + 玻璃按钮组 + 倒计时
│   ├─ StoreCardView.swift        3D 翻牌 + 品质染色玻璃 + 无障碍标签
│   ├─ EndpointsView.swift        searchable + 玻璃行 + 只看商店筛选
│   ├─ SettingsView.swift         Form + 扫描 App 文件夹 + 导出诊断
│   ├─ Theme.swift                品质→颜色映射
│   ├─ BundledConfig.plist        ★ CI 用它注入商店接口路径
│   ├─ Assets.xcassets/           AppIcon(1024) / AccentColor
│   ├─ make_icon.py               图标生成脚本（零依赖，可重跑）
│   ├─ selfcheck.py               工程自检（YAML/plist/图标/工作流断言）
│   └─ Localizable.xcstrings      String Catalog
└─ project.yml                    XcodeGen
```

> **目录说明**：工作流要放**仓库根**的 `.github/workflows/`。
> 如果你的仓库根就是 `Valorant App/`，那现在的位置就是对的；
> 如果把 `val-shop-ios/` 单独拆成一个仓库，把 `.github/` 一起挪到新仓库根，并把工作流里
> `val-shop-ios/` 前缀全部去掉即可。

---

## 一、构建与安装（你的流程）

### 推上去

```bash
git add . && git commit -m "ios" && git push
```

Actions 自动跑两个 job：

| job | 做什么 | 耗时 |
|---|---|---|
| `test` | `cd ZhangwaKit && swift test` —— 17 个用例，不联网不需要账号 | ~1 分钟 |
| `build` | XcodeGen 生成工程 → `xcodebuild` 出**未签名** app → 打包 IPA | ~5 分钟 |

构建完成后到 **Actions → 对应 run → Artifacts** 下载 `ZhangwaShop-unsigned-ipa`。

### 关键：这个 IPA 是「脏」的

工作流专门做了三件事，都是自签工具能正常吃下去的前提：

```bash
CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""   # 完全关签名
rm -rf Payload/ZhangwaShop.app/_CodeSignature                            # 清残留签名
rm -f  Payload/ZhangwaShop.app/embedded.mobileprovision                  # 清描述文件
zip -qry ZhangwaShop-unsigned.ipa Payload                                # Payload/ 为根的 zip
```

清不干净的话，ESign / 全能签这类工具会报「签名校验失败」或者直接装不上。

### 手机自签

拿到 IPA 后：下载 → 分享到 ESign / 全能签 / Scarlet → 选你的证书签 → 安装。

几个必须知道的坑：

| 坑 | 说明 |
|---|---|
| **证书有效期** | 免费 Apple ID 签的 App **7 天**就掉签，要重签。付费开发者账号（$99/年）签的是 **1 年** |
| **Bundle ID** | App 里默认 `com.example.zhangwashop`。如果你的证书不是通配符，在仓库 **Variables** 里建 `BUNDLE_ID` 改成和你证书匹配的，CI 会自动用它 |
| **重装会清数据** | 自签重装如果 Bundle ID 变了，容器会被清空 —— 登录态要重新导入。所以下面那个 `ZW_SHOP_PATH` 变量能省不少事 |
| **UDID** | 免费/个人证书要设备 UDID 在描述文件里，重装后 UDID 一般不变，不用管 |

### 省掉在手机上手输路径

商店接口路径长这样：`/go/agame/xxx/yyy`，在 iPhone 上敲很痛苦。到
**Settings → Secrets and variables → Actions → Variables** 建两个变量：

| 变量 | 值 | 作用 |
|---|---|---|
| `ZW_SHOP_PATH` | `/go/...` | 构建时写进 `App/BundledConfig.plist`，装上就有 |
| `ZW_SHOP_BODY` | `{}`（一般不用建） | 附加 JSON body |
| `BUNDLE_ID` | 你的证书对应的 ID | 覆盖默认 bundle id |

优先级的实现是：**App 里改过的 > 构建期注入的**，所以你在 App 里手动改过之后，重装新版本不会被覆盖掉。

> 注意 `ZW_SHOP_PATH` 是 **Variable 不是 Secret** —— 接口路径不是凭据。
> **Cookie / ct / token 一律不要进仓库**，全部在手机上导入。

---

## 二、拿到登录态（唯一绕不开的一步）

商店页面的接口路径**不在 APK 里**（页面是服务端下发的 RN bundle 渲染的），所以必须抓一次包。

任意一台电脑跑 Android 模拟器（MuMu / 雷电默认带 root）：

```bash
adb install com.tencent.apps.valorant.apk
adb push frida-server /data/local/tmp/ && adb shell "chmod 755 /data/local/tmp/frida-server"
adb shell "su -c /data/local/tmp/frida-server &"
frida -U -f com.tencent.apps.valorant -l ../val-shop/capture/frida_okhttp_dump.js --no-pause
```

登你的 QQ/微信 → 点开一次「每日商店」→

```bash
adb pull /data/local/tmp/mval_session.json     # 登录态，含 ct
adb pull /data/local/tmp/mval_capture.log      # 里面那条就是商店接口
```

### 丢进手机（自签环境专门优化过）

Info.plist 里开了 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`，
所以 App 的文件夹会出现在「文件」App 里：

1. 两个文件 AirDrop 到 iPhone
2. 在「文件」里移动到 **我的 iPhone → 每日商店**
3. App →「设置」→ 点 **「扫描 App 文件夹」** —— 两个文件一起读进来

不用打路径、不用一个个选。读完切到「接口」页，找带 **「疑似商店」** 角标的那条，点「设为商店接口」，
回「商店」点读取。

> **为什么必须要 ct**：`ct` 不在 Cookie 里，但它是换 `wt`（= Cookie 的 `tid`）的唯一凭据。
> 有 ct 的会话能自己续命；只有 Cookie 的话 tid 一过期就得重抓。完整推导见 `../val-shop/analysis/掌瓦数据链路分析.md` §2.1。

---

## 三、出问题了怎么查（没有 Xcode 控制台也能查）

自签装的 App 看不到 Xcode 日志，所以两处内置了排查手段：

1. **商店页底部的「运行日志」** —— 滚动，最近 12 条
2. **设置 → 维护 → 「导出诊断信息」** —— `ShareLink` 导出纯文本：登录态概览 + 商店接口 + 归一化结果 + **原始 JSON** + 全部日志

读到数据但解析不出商品时，把导出的文本发我，里面有 `rawKeys`（原始字段名）和完整 JSON，直接照着改 `StoreNormalizer` 的候选键就行。

---

## 四、Liquid Glass 怎么组织的

**所有 iOS 26 玻璃 API 只出现在 `App/LiquidGlass.swift` 一个文件里**，View 层只调封装：

```swift
.zwGlassPanel()                        // 面板玻璃
.zwGlassCard(tint: rarity.color)       // 卡片玻璃（带品质染色）
.zwGlassChip(tint: .zwMint)            // 胶囊
.zwProminentButton(tint: .zwAccent)    // .glassProminent
.zwGlassButton()                       // .glass
.zwMorphID("card-0", in: namespace)    // glassEffectID → 翻牌时玻璃 morph
.zwScrollEdge(.all)                    // scrollEdgeEffectStyle(.soft, for:)

ZWGlassGroup(spacing: 16) { … }        // GlassEffectContainer
ZWBrandBackdrop()                      // MeshGradient，让玻璃有东西可折射
```

**如果 Xcode 报某条玻璃 API 找不到或签名不对，只改 `LiquidGlass.swift`，不要动 View。**

遵守了 Apple 的几条硬性建议：玻璃间距 ≥ 20pt、不自己画 TabBar/NavigationBar/Toolbar 背景、
`.clear` 只用在媒体丰富背景上、玻璃是「控件层」而内容层保持不透明可读。

---

## 五、对照「最新 Apple 要求」

| 要求 | 实现 |
|---|---|
| Liquid Glass | `glassEffect` / `GlassEffectContainer` / `glassEffectID` / `Glass.regular·tint·interactive` / `ButtonStyle.glass·glassProminent` / `ToolbarSpacer` / `.tabBarMinimizeBehavior(.onScrollDown)` / `.scrollEdgeEffectStyle(.soft, for:)` / `MeshGradient` 底 |
| 不用回退开关 | Info.plist **刻意不写** `UIDesignRequiresCompatibility`（该开关 iOS 27 会被移除） |
| Swift 6 | `SWIFT_VERSION=6.0` + `SWIFT_STRICT_CONCURRENCY=complete`，包也设了 `.swiftLanguageMode(.v6)` |
| Approachable Concurrency | `SWIFT_APPROACHABLE_CONCURRENCY=YES` + `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` |
| 并发正确性 | 模型全 `Sendable`，`ZhangwaClient` 显式 `@MainActor`，JSON 工具标 `nonisolated` |
| Observation | `@Observable` + `@Environment(AppModel.self)`，无 `ObservableObject`/`@Published` |
| Swift Testing | `@Suite` / `@Test` / `#expect` / `#require` / 参数化用例，无 XCTest |
| App Icon | `make_icon.py` 生成的 1024 单尺寸；要上架可再用 Icon Composer 导出 `.icon` |
| 无障碍 | 卡片 `.accessibilityElement(children: .combine)` + 中文标签与提示 |
| Dynamic Type | 全语义字体，零固定 pt |
| iPhone + iPad | `TARGETED_DEVICE_FAMILY=1,2`，网格 `.adaptive` |
| String Catalog | `Localizable.xcstrings` + `STRING_CATALOG_GENERATE_SYMBOLS` |
| 沙盒化构建脚本 | `ENABLE_USER_SCRIPT_SANDBOXING=YES` |

---

## 六、本地怎么验（不用等 CI）

```bash
# 协议层：17 个用例，不联网不需要账号
cd val-shop-ios/ZhangwaKit && swift test

# 工程自检：YAML / plist / 图标 / 工作流关键断言
python3 val-shop-ios/App/selfcheck.py

# 生成工程（macOS）
cd val-shop-ios && xcodegen generate && open ZhangwaShop.xcodeproj
```

---

## 七、诚实的边界

| 部分 | 状态 |
|---|---|
| `ZhangwaKit` 协议层 | ✅ 本机 Swift 6.2.3 真实编译 + 17 个测试全过，零警告 |
| `App/` SwiftUI 层 | ⚠️ 本机是 Windows，没有 SwiftUI —— 只做到 **语法解析通过**，没做类型检查 |
| 工作流 YAML / plist / 图标 | ✅ 用 `selfcheck.py` 程序化校验过（含关键步骤断言） |
| 真实构建 | ⚠️ 没跑过。第一次 CI 可能要在 Xcode 版本 / 单条 API 签名上调一下 |

SwiftUI 层的风险已经收敛到 **一个文件**（`LiquidGlass.swift`）。
CI 第一次失败八成是那里，按注释里标注的系统能力对照 Apple 文档改一行即可。

---

## 八、排错

| 现象 | 处理 |
|---|---|
| CI: `runs-on: macos-26` 找不到 | 换成 `macos-15`，并手动指定 Xcode 26 |
| CI: `xcodegen: command not found` | 检查 `brew install xcodegen` 那步有没有被跳过 |
| 编译 `cannot find 'glassEffect' in scope` | Xcode 不是 26+，或 deployment target 低于 26 |
| 编译 `Value of type 'Glass' has no member ...` | 改 `LiquidGlass.swift` 里的 `GlassPanelModifier.glass` |
| `MeshGradient` 编译不过 | 换成 `LinearGradient`（视觉差别不大） |
| 自签工具报「签名校验失败」 | IPA 里有残留签名。确认工作流里那两行 `rm` 执行了 |
| 装完打不开 / 闪退 | 大概率是 entitlements 不匹配。自签工具里选「不使用 App 自带 entitlements」再签一次 |
| 玻璃看不见 | 背景太素。调高 `ZWBrandBackdrop` 里的透明度 |
| `[999999] 票据异常` | tid 过期。设置页点「刷新票据」；若 `ct 无` 只能重抓 |
| 读到 0 件商品 | 导出诊断信息发我，看 `rawKeys` 改 `StoreNormalizer` |
| 7 天后闪退 | 免费证书掉签，重签就行 |

---

## 九、免责

只用来读你自己账号的商店数据。别拿去批量爬或者压服务器。
