<p align="center">
  <img src="docs/assets/app-icon.png" width="128" alt="Metrilens App 图标">
</p>

# Metrilens

Metrilens 是一个仅支持 Apple Silicon、常驻 macOS 菜单栏的轻量系统状态查看器。

[更新日志](CHANGELOG.md) · [发布与安装验收清单](docs/release-checklist.md)

<p align="center">
  <img src="docs/assets/metrilens-popover.png" width="320" alt="Metrilens 状态弹窗">
</p>

它显示：

- CPU 总占用与最近 60 秒折线
- “Metrilens 占用”口径的内存使用量
- AppleSmartBattery 电池当前温度与历史最高温度
- macOS 系统热状态

它不联网、不启动外部采集进程、不请求管理员权限，也不承诺 CPU/GPU 精确摄氏温度。运行时仅使用 AppKit、Mach、IOKit 与系统电源通知；刷新频率默认为 1 秒，也可选择 2 秒或 5 秒。

## 安装

要求 macOS 13 或更高版本和 Apple Silicon Mac。

1. 从 [GitHub Releases](https://github.com/Xf-Zhou/metrilens/releases) 下载 `Metrilens-vX.Y.Z-macos-arm64.zip` 与对应的 `.sha256` 文件。
2. 在终端进入下载目录并校验文件：

   ```bash
   shasum -a 256 -c Metrilens-vX.Y.Z-macos-arm64.zip.sha256
   ```

3. 解压后把 `Metrilens.app` 拖入“应用程序”。
4. 当前版本使用本地 ad-hoc 签名且未经 Apple 公证。校验 SHA-256 并确认下载来源可信后，先尝试打开一次；若 macOS 阻止启动，请前往“系统设置 → 隐私与安全性”，在“安全性”区域点按“打开”，再选择“仍要打开”并输入登录密码。该按钮仅在尝试打开 App 后约一小时内出现；较早版本的 macOS 也可在访达中按住 Control 点击 App 后选择“打开”。详见 [Apple 官方说明](https://support.apple.com/zh-cn/guide/mac-help/mh40617/mac)。

登录启动、菜单栏主指标、刷新频率与 CPU 折线均可在设置中调整。设置损坏时 App 会自动恢复安全默认值；也可在设置窗口底部选择“恢复默认设置…”。

## 关于、诊断与快捷键

状态弹窗右上角的 ⓘ 打开“关于 Metrilens”。“复制诊断信息”只复制以下白名单内容：

- App 版本与构建号
- macOS 版本、arm64 架构和低电量模式状态
- Metrilens 的显示/刷新设置
- CPU、内存、电池温度与系统热状态

不会复制用户名、主机名、设备序列号、文件路径、IP 地址或进程 ID。

常用键盘操作：

- `⌘I`：关于与诊断
- `⌘,`：设置
- `⌘Q`：退出
- `⇧⌘C`：在“关于”窗口复制诊断信息

状态栏按钮、各指标、CPU 折线与所有设置控件均提供 VoiceOver 标签和值。

## 卸载

1. 从菜单栏弹窗退出 Metrilens。
2. 如果启用了登录启动，先在 Metrilens 设置或“系统设置 → 通用 → 登录项”中关闭。
3. 删除“应用程序”中的 `Metrilens.app`。
4. 如需同时删除偏好，可执行：

   ```bash
   defaults delete com.xfzhou.Metrilens
   ```

## 本地构建

要求 Xcode 16：

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行本地 ad-hoc Release 构建及 smoke test：

```bash
./scripts/build_local_release.sh
```

产物位于 `.build/DerivedData/Build/Products/Release/Metrilens.app`。

## 测试与 CI

普通验证不需要管理员权限，也不运行耗时的轻量化性能门禁：

```bash
./scripts/static_constraints.sh
(cd scripts && python3 -m unittest test_measure_lightweight.py test_release_tools.py)
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

GitHub Actions 在 Apple Silicon `macos-15` runner 上执行静态约束、Python 测试、Swift 测试、Release 构建及包结构验证。

完整轻量化门禁要求工作树无未提交修改，分标准与低电量两个场景，总计约 45 分钟，并需要 `fs_usage` 的管理员授权。只有在具备对应电源状态与时间条件时才运行：

```bash
sudo -v
./scripts/measure_lightweight.sh standard

# 保持接入电源并开启 macOS 低电量模式
sudo -v
./scripts/measure_lightweight.sh low-power
./scripts/measure_lightweight.sh finalize
```

详细测量窗口、原始结果完整性和门禁约束见 [设计方案](docs/design.md)。

## 发布

项目版本必须先在 Xcode 工程中更新为目标 `X.Y.Z`。本地构建确定性 ZIP、校验包结构并生成 SHA-256：

```bash
./scripts/release.sh X.Y.Z
```

产物位于 `.build/releases/vX.Y.Z/`。发布有两种入口：

- 推送 `vX.Y.Z` tag，由 GitHub Actions 自动验证、构建并创建 Release。
- 在干净工作树的目标提交上运行 `./scripts/release.sh X.Y.Z --publish`。本地脚本只创建并推送 tag；如果 tag 已存在但 Release 尚未完成，则只触发对应的 Actions workflow。

GitHub Actions 是 GitHub Release、草稿和资产的唯一写入者，并按 tag 串行执行，避免本地进程与 workflow 并发覆盖资产。发布脚本会验证源码版本、App 内版本、arm64 单架构、正式图标、App 包关键文件、ZIP 内结构和 SHA-256。相同 App bundle 会得到字节一致的 ZIP。

发布后必须从 GitHub Release 重新下载资产并执行[发布与安装验收清单](docs/release-checklist.md)，不能用本机发布目录中的 ZIP 代替远端产物验收。
