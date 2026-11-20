# iOS 高德地图

> **2026-10-21 本轮最新状态**：正常 `lib/main.dart` Profile 包已在已登录 iPad 独立确认高德主路径；两轮完整主流程通过，后一轮没有附加调试器。已修复请求取消误降级、初始化配置竞态与来源标识遮挡。长时间停留/照片返回的一次降级及完整真机故障矩阵仍待专项核验，不把下列早期冒烟失败或仅用户反馈描述当作最终状态。详细结果见本文末尾。


## 配置与构建

- 固定使用 `AMap3DMap-NO-IDFA 11.2.100` 和 `AMapFoundation-NO-IDFA 1.9.1`，版本锁在 `Podfile.lock`。
- 唯一手工凭据来源是工作区根目录 `user_info.properties` 的 `AMAP_IOS_PASSCODE`。虽然字段名含 `PASSCODE`，内容必须是绑定 iOS Bundle ID 的 SDK Key，不是 Web 安全密钥。
- 本机自定义主应用 Bundle ID 为 **`wang.xiaozhujia.immich`**。Debug/Profile/Release 使用同一 ID；Widget/ShareExtension 分别追加 `.Widget`、`.ShareExtension`，不使用主应用地图 Key 初始化 SDK。
- `Signing.local.xcconfig` 只配置本机合法签名团队、Bundle ID 和 App Group，不提交。默认上游签名设置未被替换；自定义后缀通过 `IMMICH_DEBUG_SUFFIX`、`IMMICH_PROFILE_SUFFIX` 清空。
- `pod install` 按需解析统一来源并生成 `.generated/AMap.xcconfig`（权限 `600`，Git 忽略）。Key 更新后应先执行下面的生成命令，不手工修改副本：

```sh
cd mobile/ios
ruby scripts/amap_credentials.rb
pod install
cd ..
flutter build ios --debug --no-codesign
```

独立检出可设置 `IMMICH_CREDENTIALS_FILE` 为统一来源的绝对路径。无 iOS Key 时生成空值并回退；不会借用 Android/Web Key。重复字段、无效格式和指定但不存在的来源会报错，错误不包含凭据值。运行时还检查实际 Bundle ID 与预期值一致。

未签名构建只验证编译，不可直接安装到 iPad。安装须有合法团队下覆盖主应用、两个扩展和 App Group 的开发描述文件，且包含目标设备；不使用其他应用的描述文件、不更改 Bundle ID 来绕过地图 Key 绑定、不覆盖签名不一致的现有 App。

本机已于 2026-10-20 完成上述 arm64 无签名整包编译，产物主应用及两个扩展 Bundle ID 正确、iOS Key 注入一致；这不等于签名、安装或地图实际鉴权通过。

## 实现边界

- `AmapMapPlugin` 只在前台 Flutter 引擎注册。配置查询不创建 SDK；Flutter 隐私同意后才创建 `MAMapView`，不启用用户定位。
- `immich/amap` 的 iOS `UiKitView` 与 Android 复用地图通道。iOS 通过 `initialize` 握手避免原生就绪事件早于 Dart handler；SDK错误、通道异常和30秒加载超时进入现有 MapLibre 回退。
- 地图输入与业务回调均为 WGS-84；仅原生渲染转 GCJ-02。标记、图钉、视野、点击、聚合、主题、横竖屏重布局与释放都由原生 Adapter 管理。
- SDK Logo 保持可见，额外展示 SDK 提供的审图号；缩略图不会隐藏法定标注。
- 不将 SDK 原始错误（可能含请求 URL/Key）传回 Dart，不记录照片坐标。

## 检查

```sh
ruby ios/tests/amap_credentials_test.rb
swiftc ios/Runner/Core/Map/AmapCoordinates.swift ios/Runner/Core/Map/AmapLoadPolicy.swift ios/tests/main.swift -o /tmp/immich-amap-coordinate-tests
/tmp/immich-amap-coordinate-tests
flutter test test/widgets/map
```

上述测试、类型检查和构建不能替代 iPad 真机地图验收。必须另行确认中文底图实际加载、Key 鉴权、照片标记与列表、地点选择器、明暗主题、横竖屏、重复进出和隐私拒绝回退。

## 本机首次构建门槛（2026-10-20）

用户已授权代确认三个既有 Swift 宏。本机通过 `~/.swiftpm/security/macros.json` 的精确条目批准当前 workspace 锁定的依赖，Xcode 重建已越过宏信任检查：

| 包 | 版本与提交 | 宏 |
| --- | --- | --- |
| `swift-perception` | `2.0.9` / `4f47ebafed5f0b0172cf5c661454fa8e28fb2ac4` | `PerceptionMacros` |
| `swift-structured-queries` | `0.34.0` / `dafddd843f10630aa6b5be47c1b6a59cc4ab6586` | `StructuredQueriesMacros`、`StructuredQueriesSQLiteMacros` |

信任仅针对上述提交，不关闭全局宏/插件指纹校验，不使用 `-skipMacroValidation`。升级依赖须重新检查；不能把旧指纹改为任意新值自动放行。项目级与 workspace 级 `Package.resolved` 存在原有版本差异，应以实际 workspace 构建检出的提交为准。Podfile 已移除原先自动写入全局 Xcode 跳过验证设置的两条命令，没有修改本机全局跳过设置。

### 指定账号的 Personal Team 签名与安装

此前自动签名的 `No Accounts` 阻塞已解除。用户指定账号对应 Personal Team `5D5498LPMZ`；本机配置已切换到该团队，自动创建开发证书和以下三个开发描述文件，并包含目标 iPad 与 App Group：

- `wang.xiaozhujia.immich`
- `wang.xiaozhujia.immich.Widget`
- `wang.xiaozhujia.immich.ShareExtension`

Xcode 实际拒绝 Personal Team 申请 `Access Wi-Fi Information` 和 `Associated Domains`。此前仅本机 Debug 覆盖权限；2026-10-21 为验证独立启动，Profile 也增加独立的可选本机覆盖。在 `Signing.local.xcconfig` 中配置：

```text
IMMICH_DEBUG_ENTITLEMENTS = .generated/RunnerPersonal.entitlements
IMMICH_PROFILE_ENTITLEMENTS = .generated/RunnerPersonal.entitlements
```

这个 Git 忽略的本地权限副本只保留 App Group；完整原始权限文件不改，未指定本机覆盖时 Debug/Profile 仍使用原配置，Release 始终保持原配置。这是验收包，不支持按 Wi-Fi 名称自动选择服务器，也不验证通用链接和远程推送；固定服务器地址和地图不依赖这些能力。换机可从 `Runner/Runner.entitlements` 生成本地副本，仅移除 Wi-Fi 信息和 Associated Domains；Profile 原始文件另含 `aps-environment`，本机验收副本不申请该能力。不得覆盖原文件或将本机覆盖自动用于正式发行。

本机 Debug 已完成整包签名并安装至 iPad，主应用及两个扩展的 `codesign` 严格校验通过，地图 Key/Bundle ID 相符，三个 profile 都覆盖目标设备。描述文件将于 **2026-10-27 晚（北京时间）**到期，需要届时重新构建、签名和安装，不是长期分发包。

GitHub 自有仓库此前未找到签名材料；此次签名由 Xcode 使用指定账号生成，没有借用上游团队、他人证书或其他应用的 profile，也没有导出私钥。

### 当前状态：用户确认登录后地图正常，完整交互待收尾（2026-10-21）

10 月 20 日首次启动被开发者信任阻挡；10 月 21 日已实际建立进程、LLDB 和 Dart VM 调试连接。通知权限系统弹窗也已由用户处理；正常客户端已按既有授权同意高德提示并进入服务器登录页。前台检查已通过，不再要求重新信任或点击通知。

此前独立 Debug 冒烟测试未通过：原生 SDK 失败回调返回 `NSURLErrorDomain -1004`，当时截图仅有高德 Logo、示例图钉和部分道路，且错误对象没有可用请求域名。随后用户在正常 Profile 客户端登录并明确反馈地图显示正常，因此旧错误只作历史证据，不能再作为当前客户端不可用的结论。最新地图显示结论来自用户实机反馈，本轮未独立抓图或核对提供方，不推断一定是高德主路径而非 MapLibre 回退，也不推断历史问题必由构建模式或网络授权修复；完整交互验收仍待收尾。

独立 Xcode UI 测试 Runner 此前因指定账号的 `missing Xcode-Token` / `No Accounts` 而未安装；2026-10-21 12:02（北京时间）重新执行在线自动签名已成功，为 `wang.xiaozhujia.immich.MapUITests.xctrunner` 新生成 profile，随后 Runner 已在 iPad 实际执行冷启动断言。旧账号阻塞不再成立，不需要继续退出账号或删除证书。UI 测试启动成功不等于地图测试通过。

真机入口包含活动前台前置检查与失败截图。再次执行：

```sh
IMMICH_IOS_EVIDENCE_DIR=/绝对路径/地图验收证据 \
flutter drive --no-pub \
  --driver=test_driver/amap_ios_driver.dart \
  --target=integration_test/amap_ios_smoke_test.dart \
  -d <设备ID>
```

该入口使用公开示例点，不登录 NAS、不读取图库、不清空用户数据库；核验原生加载完成回调、WGS-84 视野、标记通道、实际缩放、主题切换和重新创建，保存浅色、深色缩放和重建后的实际截图。运行它会使用已配置 Key 并初始化高德，须先取得用户隐私授权；本轮用户已明确同意。它仍不能替代照片列表联动、地点选择与横竖屏端到端验收。运行后应恢复正常主应用入口，不将测试入口当作正常客户端交付。

签名配置回归检查：

```sh
ruby ios/tests/signing_configuration_test.rb
```

签名配置检查现覆盖 Debug/Profile 本机覆盖与 Release/默认权限保留，共四项测试、28 个断言通过；截图驱动与冒烟入口此前 Dart 分析通过。此前独立冒烟入口已运行多轮但未通过；最新正常客户端地图基本显示有用户确认，仍不计作完整地图验收完成。


### 本机启动与产物核对

本机 Flutter 的 LLDB 自动启动编排曾停在日志等待阶段；可使用 Xcode 标准 `devicectl` 与 LLDB 调试已签名的本应用，并加载生成的 `Flutter/ephemeral/flutter_lldbinit`，不得关闭安全验证。调试连接仍保留认证；会话地址只放权限 `600` 的临时文件，通过 `VM_SERVICE_URL` 环境变量传给驱动，不写入仓库或命令日志。

手工安装前必须核对**实际产物内的 Dart 入口**。本机曾出现 `build/ios/iphoneos/` 仍是旧正常入口，而新测试包位于 `build/ios/Debug-iphoneos/`；仅看 `Generated.xcconfig` 不能证明已安装入口。应再通过 VM `rootLib.uri` 核对，不盲目选择同名 `.app`。

网络失败时，本轮使用已有固定 SwiftPM 依赖与 `-skipPackageUpdates -disableAutomaticPackageResolution` 完成 Xcode workspace 构建；保留 Flutter 生成/编译脚本与插件注册，不跳过宏验证。测试结束后须用 Flutter 切回 `lib/main.dart` 并恢复正常签名客户端，不能留下测试入口作交付。


### 独立启动与账号状态确认（2026-10-21）

真机已两次复现：安装的正常入口 Debug 包在不附加调试器时，Flutter 引擎显示不能独立创建调试引擎的错误页；不是等待更久就能进入应用。独立 UI Runner 的同路径断言也在等待登录按钮 12 秒后失败。日常手动体验应使用正常入口 `lib/main.dart` 的 Profile/Release；调试时才使用 Debug。不要用编译、安装、LLDB 附加和测试脚本的固定等待时间作为客户端冷启动性能。

本机 Profile 构建沿用 Flutter 生成配置和 Xcode workspace 的全部构建脚本，仅跳过已锁定 SwiftPM 依赖的联网更新：

```sh
# 在 mobile 目录，使用本机已验证的 Flutter 3.44.8。
flutter build ios --config-only --profile --no-pub --target=lib/main.dart
cd ios
xcrun xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -configuration Profile -sdk iphoneos -destination 'generic/platform=iOS' \
  -clonedSourcePackagesDirPath ../build/ios/SourcePackages \
  -skipPackageUpdates -disableAutomaticPackageResolution \
  BUILD_DIR="$PWD/../build/ios" COMPILER_INDEX_STORE_ENABLE=NO
```

安装前验证实际 Profile 产物、主应用与扩展的签名及地图 Bundle ID，按相同签名覆盖安装，不卸载、不清空应用数据。此配置是短期个人团队验收包，不是长期分发或完整权限 Release。

账号确认分三层：

1. Xcode → Settings → Apple Accounts（部分版本名为 Accounts）中能选中指定账号和 Personal Team：只说明账号记录存在。
2. Manage Certificates 能看到 `Apple Development` 且本机可签名：说明已有证书和私钥可用，仍不能单独证明在线认证正常。
3. 用 `-allowProvisioningUpdates` 为尚无 profile 的准确测试 Runner 构建，观察新 profile 的创建时间、Team ID、设备列表及 `TEST BUILD SUCCEEDED`：这是本轮实际通过的在线认证检查。再运行测试证明设备执行链路可用。

只有新一轮明确返回凭据错误，才在账号页完成重新认证；没有认证入口时再针对该账号处理，不批量清空钥匙串、撤销证书或改 Bundle ID。没有必要为了证明当前登录正常而反复新增证书或 App ID。

2026-10-21 本机最终复验：正常 Profile 包已签名原位安装；本地网络提示按既有授权处理。UI Runner 加入登录按钮可点击断言后，三次冷启动均通过，按钮检测耗时 3.350、3.342、3.345 秒（含自动化开销，不是第一帧基准）。最后不连接调试器直接启动的截图为正常登录页。主包及扩展 profile 最早于 2026-10-27 20:01:37（北京时间）到期。地图连接失败未在本轮重验，不将启动修复视为地图验收完成。


## 2026-10-21 主流程验收与已知边界

### 本轮修复

- `AmapLoadPolicy` 只忽略 `NSURLErrorDomain / NSURLErrorCancelled`（`-999`）；缩放取消旧瓦片请求不再永久切换为备用地图。其他真实失败以及加载超时回退仍保留。
- `AmapPrivacyGate` 等待配置检查完成后才创建原生地图；此前先创建的 MapLibre 会在高德之后回调、覆盖其控制器，导致照片标记未加载。配置检查五秒超时仍回退。
- iOS 地图随照片面板缩小可见画布，SDK Logo 和比例尺不被遮挡；审图号顶部放置并换行，避免小预览外溢。Android 布局不改。

### 实际验证

iPad mini 6 / iPadOS 18.7.8，正常 Profile 3.1.0，保持 Bundle ID `wang.xiaozhujia.immich` 原位安装、登录保留。两轮主流程分别约 91 秒和 90 秒，后者无调试器；该时长不是启动耗时。

已验证实际高德中文底图、自动定位到照片标记、聚合与连续缩放、照片列表和查看器返回、详情缩略图、地点选择器单图钉与草稿坐标变化、取消外层编辑、明暗主题截图、横竖屏、释放重入及来源标识可见性。没有点击外层「更新」，没有保存照片位置；测试结束恢复 System 及原方向。

自动测试：Flutter 地图 20 项、Swift 坐标/聚合/错误策略 23 断言、Ruby 签名 4/28、凭据 3/19，Dart 分析及完整 Profile 构建通过。签名严格校验通过；临时探针已从源码和最终 AOT 移除。

工作区可复跑材料位于根工作区 `.scratch/ios-map-localization/evidence/2026-10-21/MapAcceptanceUITests.swift` 与 `create_map_acceptance_probe.rb`。使用独立、本机缓存目录生成工程；运行前已登录并停留在全屏照片地图，只选择 `testFinalAcceptance`，不得把历史冷启动登录测试与此链路混跑。xcresult 包含私人照片与地点，必须仅保存在本机受控目录，不提交或复制到 NAS。

### 未关闭事项

较早分阶段、长时间停留后的照片返回曾降级为 MapLibre，未捕获当次错误码；后两轮未复现，仍需独立长时/前后台专项核验，不能宣称全部根治。隐私拒绝、无 Key、鉴权、断网与超时的完整真机注入矩阵尚未执行，自动测试不是替代品。

该 Personal Team 验收包最早签名到期仍为北京时间 **2026-10-27 20:01:37**；长期签名/分发未完成。正式默认权限不变，不把本机精简权限 Profile 当作完整发布版。

本机 Flutter 测试会重生成临时 SwiftPM manifest；本轮曾重置到 iOS 13.0，与依赖至少 14.0 冲突。最终将被忽略的生成 manifest 对齐产品既有 iOS 15.0，再使用固定本机依赖缓存构建成功，没有改产品支持版本。网络不可用时 config-only 可能在依赖更新处失败，不能把这种失败当作完整配置成功；后续生成配置后仍需检查目标版本。不要并发执行会重写这些文件的测试/配置与产品构建。
