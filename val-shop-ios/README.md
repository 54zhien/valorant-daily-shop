# 无畏契约 · 每日商店（iOS 26 / Liquid Glass · 入荷板）

原生 SwiftUI 的独立每日商店 App。**代码推 GitHub → Actions 出未签名 IPA → 手机上自签安装。**

> **✅ 2026-10-18 实机验证通过**：iPhone 上自签安装后成功读到真实每日商店数据。
>
> 接口：`POST /go/mlol_store/agame/user_store`，body `{}`。
> 完整逆向过程见 [`../val-shop/analysis/掌瓦数据链路分析.md`](../val-shop/analysis/掌瓦数据链路分析.md) §2。
>
> **🎨 2026-10-19 UI 大改**：材质是 Liquid Glass，版面重排成「入荷板」
> （引信条 + 状态只说人话 + 底栏两个页签）。**面向普通用户**：开发工具全部收进
> 收在「关于 → 诊断」里，普通用户碰不到。视觉事实来源是 [`design/preview.html`](design/preview.html)，
> 改法与 token 见 §四。

## ⚠️ 用之前必须知道的一件事

**`wt`（Cookie 里的 `tid`）只有 30 分钟有效期。**

```
refresh_wt_span = 1800     wt  30 分钟   ← 很容易过期
refresh_ct_span = 604800   ct   7 天
```

所以**不要试图存一份长期有效的 Cookie** —— 过半小时就废。
正确做法是导入带 `ct` 的登录态，App 遇到 `999999 票据异常` 会自动用 `ct` 换新 `wt` 再重试。

如果连 `ct` 也过期了（7 天），只能重新抓一次包。


技术栈按 Apple 2025–2026 最新要求：**iOS 26 部署目标 + Liquid Glass 全家桶 + Swift 6 严格并发 + Observation + Swift Testing**。

```
val-shop-ios/
├─ .github/workflows/ios.yml      ← 在仓库根的 .github/ 下，见下方目录说明
├─ ZhangwaKit/                    ✅ 已验证：swift test 17/17 通过，零警告
│   ├─ Package.swift              swift-tools-version 6.0，Swift 6 语言模式
│   ├─ Sources/ZhangwaKit/        协议层（Sendable 模型 + @MainActor client）
│   └─ Tests/ZhangwaKitTests/     Swift Testing（@Suite / @Test / #expect）
├─ App/                           ⚠️ 需在 Xcode 26 上编译（本机无 SwiftUI）
│   ├─ ZhangwaShopApp.swift       @main + TabView（两个页签）+ 登录 sheet
│   ├─ DesignSystem.swift         ★ 全项目 token：色板 / 圆角 / 字阶 / 玻璃块 / 列表零件
│   ├─ LiquidGlass.swift          ★ 全项目唯一直接调 iOS 26 玻璃 API 的文件 + 品牌底
│   ├─ AppModel.swift             @Observable + @MainActor
│   ├─ ShopView.swift             身份条 + 入荷板（引信条）+ 主按钮 ← 普通人的主界面
│   ├─ FlipCard.swift            ★ 翻牌容器：一个进度值驱动旋转/换面/抬升/投影/边缘透光
│   ├─ StoreCardView.swift        卡片内容：卡背序号 + 卡面品质钻标 + 画 + 信息块
│   ├─ ProfileView.swift          「我的」：状态 / 扫码登录 / 角色 / 退出 / 关于
│   ├─ DiagnosticsView.swift      ★ 诊断台（List，入口在「我的 → 关于 → 诊断」）
│   ├─ EndpointsView.swift        抓包接口清单（诊断台里的子页）
│   ├─ QRLoginView.swift          微信扫码（取景框 + 状态钻）
│   ├─ QQLoginView.swift          QQ 扫码（WKWebView + 诊断面板）
│   ├─ RolePickerView.swift       多角色切换
│   ├─ Theme.swift                模型 → 视图的取值助手（品质色、价格千位、会话健康度）
│   ├─ BundledConfig.plist        ★ CI 用它注入商店接口路径
│   ├─ Assets.xcassets/           AppIcon(1024) / AccentColor
│   ├─ make_icon.py               图标生成脚本（零依赖，可重跑）
│   ├─ selfcheck.py               工程自检（YAML/plist/图标/**Swift 语法**/设计资产）
│   └─ Localizable.xcstrings      String Catalog
├─ design/                        ★ 设计预览台（视觉事实来源）
│   ├─ preview.html               单文件、零依赖：七个界面 + token 板，可点可翻
│   └─ shoot.ps1                  渲染成一堆 PNG（Windows 上也能跑，不用 Xcode）
├─ probe/                         ★ 本机能跑的两个验算台（不参与 App target）
│   ├─ isolation_probe.swift      并发隔离语义（MainActor-by-default 下 Shape 怎么写）
│   └─ geometry_probe.swift       切角/品质钻/斜纹/网格的路径点对账
└─ project.yml                    XcodeGen
```

> `design/` 与 `probe/` 不在 App target 里（`project.yml` 只收 `App/`），
> 所以里面放可执行脚本和实验代码都不会进包。

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

### 从手机上下载（推荐）

每次 push 到 `main`，CI 会把 IPA 挂到一个滚动 Release 上，给你一条**能直接点的直链**：

```
https://github.com/54zhien/valorant-daily-shop/releases/download/latest/ZhangwaShop-unsigned.ipa
```

Safari 里点开 → 分享 → 丢给 ESign / 全能签。不用登录 GitHub、不用去 Actions 翻 Artifacts
（那边下下来是个 zip，iOS 还得先解压，很烦）。

也可以去 [Releases 页面](https://github.com/54zhien/valorant-daily-shop/releases/tag/latest) 手点下载。

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

> 现在这条路只在**排障**时用（普通用户直接扫码登录）。入口：
> `我的 → 关于 → 诊断`。

Info.plist 里开了 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`，
所以 App 的文件夹会出现在「文件」App 里：

1. 两个文件 AirDrop 到 iPhone
2. 在「文件」里移动到 **我的 iPhone → 每日商店**
3. 诊断台 → 点 **「扫描 App 文件夹」** —— 两个文件一起读进来

不用打路径、不用一个个选。读完进 **诊断台 → 接口清单**，找带 **「疑似商店」** 角标的那条，
点「设为商店接口」，回「商店」点读取。

> **为什么必须要 ct**：`ct` 不在 Cookie 里，但它是换 `wt`（= Cookie 的 `tid`）的唯一凭据。
> 有 ct 的会话能自己续命；只有 Cookie 的话 tid 一过期就得重抓。完整推导见 `../val-shop/analysis/掌瓦数据链路分析.md` §2.1。

---

## 三、出问题了怎么查（没有 Xcode 控制台也能查）

自签装的 App 看不到 Xcode 日志，所以留了一个**藏起来的**诊断台：

> **入口：`我的 → 关于 → 诊断`**（见 `ProfileView` 的「关于」分区）

里面是：上次读取结果、全部动作（读取 / 刷新票据 / 探测接口 / 恢复默认 / 演示数据 / 导入抓包文件）、
粘贴登录态、抓包接口清单、运行日志（最近 80 行）、导出诊断信息。

**为什么藏起来**：这一页的每个词（票据 / ct / 接口 / 抓包）对普通用户都没有意义。
台面上只留一句话人话提示，出问题时才出现：

| 情况 | 首页会说什么 |
|---|---|
| 没登录 | 还没登录 —— 登录一下就能看今天的商店 |
| 登录快过期 / 不能自刷新 | 登录状态快到期了，建议到「我的」重新扫一下码 |
| 读取失败 | 没读到商店：<原因>。点下面按钮再试一次 |

读到数据但解析不出商品时：诊断台点「导出诊断信息」，把文本发我 —— 里面有 `rawKeys`
（原始字段名）和完整 JSON，直接照着改 `StoreNormalizer` 的候选键就行。

---

## 四、这一版 UI 怎么来的（按 Apple 文档做，不自己发挥）

> 视觉事实来源：[`design/preview.html`](design/preview.html) —— 单文件、离线、能点开翻牌。
> 它现在用的是 **iOS 深色模式下的系统真值色**（`#000000` / `#1C1C1E` / `rgba(235,235,245,.6)`…），
> 所以预览里看到的，就是真机上大概的样子。

### 六条硬规矩（都是文档里的，不是我拍的）

| 规矩 | 出处 | 落地方式 |
|---|---|---|
| 字号走 Dynamic Type，不写死点数 | HIG Typography / [Scaling fonts automatically](https://developer.apple.com/documentation/UIKit/scaling-fonts-automatically) | 全项目 **0 处** `.font(.system(size:))`，只有 `.caption2 / .caption / .footnote / .subheadline / .callout / .body / .headline / .title3` |
| 文字用语义色，颜色定义在资产目录 | [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color) / [Supporting Dark Mode](https://developer.apple.com/documentation/UIKit/supporting-dark-mode-in-your-interface) | 文字只有 `.primary / .secondary / .tertiary`；底色只有 `Color(.systemBackground)` / `.secondarySystemGroupedBackground` / `.tertiarySystemFill`；品牌红、青绿进 `Assets.xcassets`（`zwRouge` / `zwSignal`）；`Info.plist` 声明 `UIUserInterfaceStyle = Dark` |
| 玻璃是**控件层**的材质 | [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | TabBar / NavigationBar / sheet / `.glassProminent` 按钮 —— 全部由系统提供。内容层（卡片、分组、身份卡）不透明。项目里**不再自己调 `glassEffect`** |
| 设置类内容用 List / Form | [HIG Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) | 「我的」「诊断台」「抓到的接口」「切换角色」都是 `List` + `LabeledContent`，分隔线 / VoiceOver / 键盘导航全是白拿的 |
| 自定义手势不能是唯一入口 | [HIG Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures) | 诊断台改成「我的 → 关于 → 诊断」一行明码，不再靠长按版本号 |
| 自定义控件要报值 | [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | 引信条报 `accessibilityValue("NN%")`；卡片报「第 N 张 / 名称 / 价格 / 已拥有」 |

### 版面

```
[ 每日商店 ]                       ← NavigationStack，inline 标题（玻璃，系统）
 身份卡   头像 · 游戏ID · 段位 ············ ◆ 已登录
 DAILY STORE          16:47:08    [翻开全部]
 ─────────────────────────────── ← 引信条：今天的进度
 ┌────────┐ ┌────────┐
 │  画    │ │  画    │             内容卡：不透明 4:5
 ├────────┤ ├────────┤             上画 / 下信息，中间系统分隔线
 │ 名字    │ │ 名字    │
 │ 1290 VP │ │ 1290 VP │
 └────────┘ └────────┘
 LINE-UP · 4   紫×2 金×1   合计 7 550 VP
[ 读取今日商店 ]                    ← .glassProminent（控件层）
[ 商店 ][ 我的 ]                    ← TabView，iOS 26 自带玻璃与 morph
```

一屏放得下四张卡（6:7）。小屏机（SE）会滚一点，这是取舍不是 bug。

**卡面画心的尺寸归一**：皮肤图的画布并不统一（实测 512×116 / 512×144 / 512×196，
内容宽高比 2.5–3.8）。直接 `scaledToFit` 的话，越「方」的图（短枪、近战）高度越顶格，
看着比长枪大一圈。所以按「**视觉面积相同 + 高度封顶**」排（见 `ZW.artAreaFraction` /
`artHeightCap` 与 `CachedImage.normalizedSize`）：

| 图 | 之前 | 现在 |
|---|---|---|
| 长枪 3.8:1 | 165×43 | 153×40 |
| 獠牙 2.5:1 | 165×66 | 124×50 |
| 短枪 1.4:1 | 164×**117** | 93×66 |
| 近战 1.0:1 | 117×117 | 73×73 |

四张的面积基本一致（约 6 178 pt²），高度差从 2.7× 收到 1.8×。

### 翻牌动效：一个进度值驱动全部效果

不再是"旋转一段 + 延迟换面一段"，而是 `FlipCard.swift` 里**一个 `progress: 0→1`**，
其余全是它的函数：

点击之后按顺序发生这些事，全部是 `progress` 的一段窗口函数（`window(p, from:to:)`）：

| 时间段 | 发生什么 |
|---|---|
| `0.00 – 0.05` | 品质光起头（很快亮起来，不硬切） |
| `0.02 – 0.46` | **品质光绕卡一圈**，`flow()` = 起步 8% 加速 → 匀速，走到 `0.46` 正好合拢（616ms）；走过的轨迹立刻留下 |
| `0.02 – 0.46` | **向顶部抬升**（位移 7pt + 放大 4%），**和扫圈同一个窗口** —— 光走完一圈的同一刻，卡抬到最高 |
| `0.46 – 0.50` | **定格一拍**（约 56ms）：一圈刚合拢、卡停在最高点 |
| `0.50 – 0.92` | **翻转**（抬着翻），末尾 3.2° 过冲再回正 |
| `0.71` | **换面** —— 翻转行程的中点，卡片侧对镜头，看不见 |
| `0.92 – 1.00` | **落下**，阴影收拢；整圈光收到 `ZW.flipGlowResting = 0.70` 常亮 |
| `0.39 – 0.46` | 光头淡出（**合拢即收**，不留一颗亮头挂在卡上） |
| `0.62 – 1.00` | **卡外那圈淡光**（`outerHalo`）从卡边渗出来，常亮 `ZW.flipHaloResting = 0.45` |

总时长 `ZW.flip = 1.4s`，四张错开 130ms，连起来约 1.8s。
**可逆**：翻到一半再点，进度从当前值往回走，整段编排倒放。

> **顺序上的硬规矩：光环走完一圈，卡才翻。** 光还在跑就翻，两件事会撞在一起
> （最早那版扫圈窗口铺到 `1.00`、翻转 `0.45` 就起步，就是这个毛病）。
> 现在三个窗口的先后由 `probe/flow_probe.swift` 的「时序」段逐条守着：
> 扫满 `p=0.46`（644ms）→ 抬到最高 `p=0.46`（同一刻，差 0ms）→ 起翻 `p=0.50`（晚 56ms），
> 并且 `rotationAngle(0.46) == 0`（光没走完之前卡一点都不转）。
>
> **速度曲线**：`flow()` 只在起步 8% 加速，之后匀速 —— 扫 360° 用 616ms（584°/s），
> 84 帧里动帧 38 帧、最大/平均 1.071。收尾**不减速**：圆环是周期图形，
> 走满 360° 正好接回起点，减速反而像"光卡在终点"；停车感交给光头淡出。

> **卡外那圈光**（`outerHalo`）：外扩 `ZW.flipHaloInset = 4pt` 的圆角描边 + 同量模糊，
> 画在**不透明卡底后面** —— 只在卡片轮廓外面露出来，卡内一点不被冲淡。
> 外扩约 10pt，所以 2×2 卡阵间距用了 `ZW.cardGap = 20`：相邻两张各留 10pt，
> 光刚好留在自己那块地方。想加粗外晕，先把 `cardGap` 一起放大。

> **光怎么画的**：`ZWRingSweep` 按**弧长**在圆角矩形轮廓上采样成折线。
> 不能用 `Shape.trim` —— 它按路径参数分段切，直线段和四段圆弧会被切碎，
> 表现就是光在拐角处"分成几块"（踩过两次）。
> 几何验算台：[`probe/ring_probe.swift`](probe/ring_probe.swift) —— 9 项全过，
> 采样间距实测 0.350 完全均匀。
>
> **零长度的 sweep 不画**（`from == to` → 空路径）：起点在上边中点，
> 零长度折线配上 `lineCap: .round` 会在那儿戳出一个圆帽 ——
> 未翻开的卡顶上那颗光点就是它。`ringOpacity` 在 `progress == 0` 时也硬返回 0，
> 双层保证「没翻开的卡一点光都没有」（`⑦` 那条退化检查在验算台里）。

> 那道光用的是**品质色**（`accent`）。不想在翻之前剧透档位，就把 `StoreCardView` 里
> 传的 `accent: tint` 换成 `accent: .white` —— 一行。
> 「减弱动态效果」开着时：不跑圈、不位移、不旋转，光改成整体淡入淡出 + 卡面交叉淡入。

四张依次翻开，错开 `130ms`。开「减弱动态效果」时不做 3D，进度直接当透明度用（纯交叉淡入）。

> `animatableData` 必须显式 `nonisolated`（本项目默认隔离是 MainActor）。
> 验算台：[`probe/animatable_probe.swift`](probe/animatable_probe.swift)，三种写法 + 一组会失败的对照。

> 玻璃卡片之间的 morph 效果没了。卡片现在是**内容**，内容层不上玻璃（规矩三）。

### token 在哪（`App/DesignSystem.swift`）

| 类别 | 用什么 |
|---|---|
| 文字层级 | `.primary` / `.secondary` / `.tertiary` |
| 内容底 | `Color(.secondarySystemGroupedBackground)` → `zwContentBackground()` |
| 页面底 | `Color(.systemBackground)` / `.systemGroupedBackground` |
| 品牌色 | `zwRouge` `#FF4655`、`zwSignal` `#00E0C6`（`Assets.xcassets` 里的 colorset） |
| 品质五档 | `Rarity.colorHex` —— 服务端数据（掌瓦 `ic_val_goods_quality_1..5`），**不可改** |
| 字号 | Dynamic Type 文本样式，见上表 |
| 两处腔调 | 机器腔 `.system(style).weight(.heavy).width(.compressed)`（**只排拉丁小标**）；数据腔 `.system(style, design: .monospaced)` |
| 几何 | 分组 16 / 卡片 20 / 小控件 11 / 发丝线 1 / 页边 16 / 块间距 12 / **卡阵间距 20**（`cardGap`，留地方给翻牌的外晕） |
| 自绘形状 | `ZWDiamond`、`ZWHatchTexture` —— 附几何验算台 |

### 冷启动与图片缓存

冷启动要快，两件事必须本地化（细节见 `App/ImageStore.swift` 与 `AppModel` 的「冷启动缓存」段）：

| 东西 | 做法 |
|---|---|
| 商店 + 角色 | 上一期读到的写本地，`init()` 里**同步**铺上屏；命中「这一期」就完全不发请求，角色丢后台刷 |
| 皮肤图 | 内存 `NSCache` + 磁盘缩略图（**降采样到 340px 存 PNG**，约 20–40 KB）；请求用 `.returnCacheDataElseLoad`，有就用、不问服务器 |

为什么必须自己做：皮肤图 `Cache-Control` 只有 `max-age=600`，过期后每次冷启动都要付一次
304 往返；`AsyncImage` 又不能设 `cachePolicy`，所以加载器是自己写的（`CachedImage` + `ImageStore`）。

**存 PNG 不存 JPEG**：真实皮肤图（`game.gtimg.cn/.../WeaponSkins/*.png`）实测 512×144、
**RGBA 带透明通道**、63 KB。JPEG 没有 alpha，会把透明底压成实色 —— 武器后面就多一块白框
（第一版踩过，所以缓存目录带版本号 `zwimg-png-v1`，旧的白框缩略图整批作废）。

**验收方法**（最干脆）：看一遍商店 → **开飞行模式** → 杀进程 → 冷启动。
四张卡该立刻在，皮肤图也该在（磁盘缩略图）。图没了就说明缓存没生效。
### 预览台与验算台（Windows 上也能跑）

```powershell
# 渲染设计预览成 PNG（不需要 Xcode，不需要联网）
powershell -File val-shop-ios/design/shoot.ps1
# 出图：design/shots/  s1-store  s2-revealed  s3-empty  s4-diagnostics
#                       s5-endpoints  s6-profile  s7-login   （默认 2x）

# 并发隔离语义：MainActor-by-default 下自定义 Shape 该怎么写
cd val-shop-ios/probe
swiftc -typecheck -swift-version 6 -default-isolation MainActor `
       -strict-concurrency=complete isolation_probe.swift

# 几何对账：品质钻 / 卡背斜纹的路径点真的算出来对一遍
swiftc -O geometry_probe.swift -o geo.exe; .\geo.exe
swiftc -O ring_probe.swift -o ring.exe; .\ring.exe

# 翻牌编排时序：光扫满 → 抬到最高 → 停一拍 → 才翻（含速度曲线与旧版对照）
swiftc -O flow_probe.swift -o flow.exe; .\flow.exe
```

> `isolation_probe.swift` 不是作业，是**结论的存档**：它证明了在这个 target 的设置下
> （`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + Swift 6 严格并发）
> `OptionSet` 的一致性会被推成 MainActor 隔离、在 `nonisolated func path(in:)` 里用不了。
> 自定义 shape 之前先跑一遍它。

## 五、对照「最新 Apple 要求」

| 要求 | 实现 |
|---|---|
| Liquid Glass | 玻璃**只作控件层材质**（HIG Materials）：`TabView` / `NavigationStack` / `.sheet` 全由系统出玻璃；按钮用 `ButtonStyle.glass` ⇄ `glassProminent`；`.tabBarMinimizeBehavior(.onScrollDown)`；`.scrollEdgeEffectStyle(.soft, for:)` 走 `zwScrollEdge()`。项目内**已无一处**直接调 `glassEffect` |
| 内容层材质 | 不透明：`Color(.systemBackground)` / `.secondarySystemGroupedBackground` / `.tertiarySystemFill`，全部系统语义色 |
| 颜色来源 | 品牌红青绿在 `Assets.xcassets` 的 colorset；文字只用 `.primary/.secondary/.tertiary`（HIG Color） |
| 外观 | `Info.plist` 声明 `UIUserInterfaceStyle = Dark`，纯深色 App（HIG Supporting Dark Mode） |
| 字体 | 全部 Dynamic Type 文本样式；两处腔调 = 系统字体 + `weight`/`width`/`design`，无第三方字体（HIG Typography） |
| 设置类页面 | `List` + `LabeledContent` + `Section(header:footer:)`（HIG Lists and tables） |
| 手势 | 不用隐藏手势做唯一入口；诊断入口是「我的 → 关于 → 诊断」一行（HIG Gestures） |
| **面向普通用户** | 底栏两个页签（商店 / 我的）；界面上不出现「票据 / ct / 接口 / 日志 / 抓包」 |
| 不用回退开关 | Info.plist **刻意不写** `UIDesignRequiresCompatibility`（该开关 iOS 27 会被移除） |
| Swift 6 | `SWIFT_VERSION=6.0` + `SWIFT_STRICT_CONCURRENCY=complete`，包也设了 `.swiftLanguageMode(.v6)` |
| Approachable Concurrency | `SWIFT_APPROACHABLE_CONCURRENCY=YES` + `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` |
| 并发正确性 | 模型全 `Sendable`，`ZhangwaClient` 显式 `@MainActor`，JSON 工具标 `nonisolated` |
| Observation | `@Observable` + `@Environment(AppModel.self)`，无 `ObservableObject`/`@Published` |
| Swift Testing | `@Suite` / `@Test` / `#expect` / `#require` / 参数化用例，无 XCTest |
| App Icon | `make_icon.py` 生成的 1024 单尺寸；要上架可再用 Icon Composer 导出 `.icon` |
| 无障碍 | 卡片 `.accessibilityElement(children: .combine)` + 中文标签与提示；引信条报 `accessibilityValue`（HIG Accessibility） |
| Dynamic Type | 语义字号；卡片内文字给 `lineLimit` + `minimumScaleFactor`，Dynamic Type 拉到最大时不会撑破卡 |
| 减弱动态效果 | `accessibilityReduceMotion` 打开时，翻牌从 3D 旋转降级成交叉淡入 |
| iPhone + iPad | `TARGETED_DEVICE_FAMILY=1,2`，板子限宽 520pt 居中（`ZW.boardMaxWidth`） |
| String Catalog | `Localizable.xcstrings` + `STRING_CATALOG_GENERATE_SYMBOLS` |
| 沙盒化构建脚本 | `ENABLE_USER_SCRIPT_SANDBOXING=YES` |

---

## 六、本地怎么验（不用等 CI）

```bash
# ① 协议层：17 个用例，不联网不需要账号
cd val-shop-ios/ZhangwaKit && swift test

# ② 工程自检：YAML / plist / 图标 / Swift 语法 / 设计资产（Windows 上就能跑）
python val-shop-ios/App/selfcheck.py
#   └ 里面有一项会调 swiftc -parse 扫全部 App/*.swift（语法层，不需要 Apple SDK）

# ③ 兜底体检：找「被 shell 吃掉的引号/美元符/绑定变量」
python val-shop/capture/lint_swift_shell_damage.py

# ④ 设计预览台（改 UI 先看这个）
powershell -File val-shop-ios/design/shoot.ps1

# ⑤ 生成工程（仅 macOS）
cd val-shop-ios && xcodegen generate && open ZhangwaShop.xcodeproj
```

**本机能验什么、不能验什么，说清楚**：

| 检查 | 本机（Windows） | 说明 |
|---|---|---|
| Swift 语法 | ✅ `swiftc -parse` | 括号/引号/缺逗号这类 |
| 并发隔离语义 | ✅ `probe/isolation_probe.swift` | MainActor-by-default 下哪些写法会炸 |
| 形状几何 | ✅ `probe/geometry_probe.swift` | 切角/钻标/斜纹的路径点逐点对账 |
| 协议层逻辑 | ✅ `swift test` | ZhangwaKit 那 17 个用例 |
| **SwiftUI 类型检查** | ❌ | 没有 Apple SDK，只能等 CI（macOS + Xcode 26） |
| **运行时外观** | ❌ | 要装到手机上才看得到 |

---

## 七、诚实的边界

| 部分 | 状态 |
|---|---|
| `ZhangwaKit` 协议层 | ✅ 本机 Swift 6.2.3 编译 + 17 个测试全过；CI（macOS + Xcode 26）也全过 |
| `App/` SwiftUI 层（大改前那一版） | ✅ **CI 上真实编译通过**（iOS 26 SDK / Xcode 26 / arm64） |
| `App/` SwiftUI 层（本次大改后） | ⏳ 本机只做了**语法 + 几何 + 隔离语义**三层验证；类型检查要等 CI |
| Liquid Glass API | ✅ 编译通过，且二进制里确认链上了 `glassEffect` / `GlassEffectContainer` / `tabBarMinimizeBehavior` / `scrollEdgeEffectStyle` |
| 未签名 IPA | ✅ 产出并校验：Payload 结构正确、无 `_CodeSignature` 残留、`MinimumOSVersion 26.0`、arm64、图标已编译、`BundledConfig.plist` 已注入 |
| 滚动 Release 直链 | ✅ 实测 HTTP 206 可下载，返回 PKZIP |
| 真机运行 | ⚠️ 没跑过 —— 需要你自签装到手机上才能确认运行时行为 |

### 第一次 CI 挂在哪，修了什么

留个记录，以后改 `LiquidGlass.swift` 时能少踩一次：

```
EndpointsView.swift:70: error: type 'ShapeStyle' has no member 'zwMint'
LiquidGlass.swift:73:   error: type 'some Hashable' does not conform to the 'Sendable' protocol
```

1. `.foregroundStyle(.zwMint)` 这种写法要求成员挂在 **`ShapeStyle`** 上，光有 `extension Color`
   不够（SwiftUI 内置的 `.blue` / `.red` 也是declare两份）。补了一份
   `extension ShapeStyle where Self == Color`。
2. `glassEffectID` 的签名是 `some Hashable & Sendable`，Swift 6 严格并发下
   `some Hashable` 不够，得写全。

**其余玻璃 API 一次过**，包括 `MeshGradient`、`GlassEffectContainer`、`ToolbarSpacer`、
`tabBarMinimizeBehavior`：说明按文档写的签名都是对的。

### 大改这一版，本机提前排掉了哪些坑

大改动了十几个文件，本机没有 SwiftUI，所以先把**能离线验的都验了**再交出去：

| 坑 | 怎么发现的 | 结论 |
|---|---|---|
| **会翻的那层不能上模糊/裁剪** | 渲染预览台时翻牌只剩卡背 | `backdrop-filter` / `clip-path` / `clipShape` 都会压平 3D 上下文。玻璃挂在**面上**（HTML）或**容器上**（SwiftUI 的 `zwGlassCard` 挂在旋转外层），两者只能选一个位置 |
| **字压在玻璃上会糊** | 预览台里卡片底部的字被玻璃底色顶掉对比度 | meta 区垫一层压暗渐层，但比不透明版轻（`.42 → .66` 而不是 `.78 → .96`） |
| `OptionSet` 的一致性会被推成 MainActor 隔离 | `probe/isolation_probe.swift` | 自定义 shape 在 `path(in:)` 里只读实例属性；别碰 static token 和协议合成成员 |
| `.kerning` / `.monospacedDigit` 是 **Text** 的方法 | 查 Apple 文档 | 这两个 helper 定义在 `extension Text` 上，不用 `View` 版本 |
| 绝对定位的纹理层会盖住所有静态内容 | 预览台第一版把整页文字蒙灰 | 底纹并进背景，不要用覆盖层（玻璃版已经不需要底纹） |


---

## 八、排错

| 现象 | 处理 |
|---|---|
| CI: `runs-on: macos-26` 找不到 | 换成 `macos-15`，并手动指定 Xcode 26 |
| CI: `xcodegen: command not found` | 检查 `brew install xcodegen` 那步有没有被跳过 |
| 编译 `cannot find 'glassEffect' in scope` | Xcode 不是 26+，或 deployment target 低于 26 |
| 编译 `Value of type 'Glass' has no member ...` | 改 `LiquidGlass.swift` 里的 `GlassPanelModifier.glass` |
| 编译 `value of type 'Font' has no member 'width'` | `DesignSystem.swift` 的 `Font.zwMachine`，删掉 `.width(.compressed)` 即可 |
| 编译报 `main actor-isolated ... nonisolated context` | 大概率是往 `path(in:)` 里塞了 static token。跑 `probe/isolation_probe.swift` 复现 |
| 自签工具报「签名校验失败」 | IPA 里有残留签名。确认工作流里那两行 `rm` 执行了 |
| 装完打不开 / 闪退 | 大概率是 entitlements 不匹配。自签工具里选「不使用 App 自带 entitlements」再签一次 |
| 玻璃看不见 / 一片糊 | 背景太素。`ZWBrandBackdrop` 的两团柔光是玻璃的"折射物"，别把透明度调低 |
| 卡面上的字发灰 | meta 的压暗渐层太薄。调 `StoreCardView.meta` 里那两个 `Color.zwInk.opacity(...)` |
| `[999999] 票据异常` | tid 过期。诊断台点「刷新票据」；若 `ct 无` 只能重抓 |
| 读到 0 件商品 | 诊断台「导出诊断信息」发我，看 `rawKeys` 改 `StoreNormalizer` |
| 7 天后闪退 | 免费证书掉签，重签就行 |

---

## 九、免责

只用来读你自己账号的商店数据。别拿去批量爬或者压服务器。
