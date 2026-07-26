# 发布与安装验收清单

本文适用于 Metrilens 的 `vX.Y.Z` 发布。当前产品边界是 Apple Silicon、macOS 13 或更高版本、ad-hoc 签名且未公证。

## 1. 发布前

- [ ] 目标版本已经写入 Xcode 工程，`CHANGELOG.md` 已把对应内容从“未发布”移动到目标版本。
- [ ] 工作树干净，当前分支和 `origin/main` 同步。
- [ ] 本次发布不增加 Intel 架构、联网、管理员权限或外部采集进程。
- [ ] 执行普通验证：

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

- [ ] 仅在具备时间、电源状态和管理员授权时执行约 45 分钟的标准/低电量轻量化门禁；普通补丁发布不把它当作默认前置条件。

## 2. 发布

- [ ] 在目标提交和干净工作树上执行：

  ```bash
  ./scripts/release.sh X.Y.Z --publish
  ```

- [ ] 确认 `vX.Y.Z` tag 指向目标提交。
- [ ] 确认 Release workflow 成功。GitHub Actions 必须是 Release、草稿和资产的唯一写入者。
- [ ] Release 页面至少包含以下两个资产：

  - `Metrilens-vX.Y.Z-macos-arm64.zip`
  - `Metrilens-vX.Y.Z-macos-arm64.zip.sha256`

## 3. 远端产物验收

必须从 GitHub Release 重新下载，不能用本机发布目录中的 ZIP 代替。推荐直接执行：

```bash
./scripts/accept_release.sh X.Y.Z
```

脚本会把远端资产下载到隔离临时目录，并检查 SHA-256、ZIP 结构、版本、arm64 架构、签名和 10 MiB 体积上限。需要额外做 3 秒启动检查时使用 `--smoke`；复验已下载资产时使用 `--from-dir DIR`。

- [ ] 在未登录浏览器或无凭据的请求中确认下载可见。若计划公开分发，匿名访问返回 `404` 即为发布阻断项。
- [ ] 校验下载文件：

  ```bash
  cd ~/Downloads
  shasum -a 256 -c Metrilens-vX.Y.Z-macos-arm64.zip.sha256
  ```

- [ ] 确认 Release 页面显示的 ZIP digest 与本地 `shasum -a 256` 一致。
- [ ] 解压到临时目录并检查包结构、版本、架构和签名：

  ```bash
  acceptance_dir="$(mktemp -d "${TMPDIR:-/tmp}/metrilens-acceptance.XXXXXX")"
  ditto -x -k Metrilens-vX.Y.Z-macos-arm64.zip "$acceptance_dir"

  python3 /path/to/Metrilens/scripts/release_tools.py \
    check-bundle "$acceptance_dir/Metrilens.app" X.Y.Z
  codesign --verify --deep --strict --verbose=2 \
    "$acceptance_dir/Metrilens.app"
  lipo -archs "$acceptance_dir/Metrilens.app/Contents/MacOS/Metrilens"
  du -sk "$acceptance_dir/Metrilens.app"
  ```

  预期为单一 `arm64`，App 小于 10 MiB。

- [ ] 确认浏览器下载的 ZIP 带有 `com.apple.quarantine`。当前版本未公证，Gatekeeper 可能拦截首次打开；提示和 README 安装说明必须一致。
- [ ] 按 README 的“隐私与安全性 → 仍要打开”路径完成人工首次打开。不要在自动化脚本中替用户绕过安全提示。

## 4. 两分钟功能检查

- [ ] 菜单栏出现 Metrilens 状态项，点击后能正常打开和关闭弹窗。
- [ ] CPU 与内存显示有效值，CPU 折线会随采样更新。
- [ ] CPU 与内存的平均值、峰值和折线悬停读数合理。
- [ ] 电池存在时温度状态合理；无电池或暂不可读时不显示旧值为当前值。
- [ ] 电池电量、供电状态、循环次数和健康状态与系统信息合理一致。
- [ ] 电池本次运行最高温度可以重置；设备历史最高温度不受影响。
- [ ] 网络下载/上传速率在空闲与传输时变化合理，切换主接口后不会显示异常峰值。
- [ ] 启动磁盘已用与可用容量合理，低空间语义色正确。
- [ ] 系统热状态显示正常。
- [ ] 异常发热诊断在正常状态不误报；模拟高 CPU/高温时展示依据、建议和“活动监视器”说明。
- [ ] 单项/紧凑菜单栏模式、指标排序、分隔符、精度和中英文界面切换正常。
- [ ] 本地提醒默认关闭；六类开关、权限状态、测试提醒与系统设置入口正常；应用位于前台时仍显示横幅并播放提示音。
- [ ] `⌘I` 打开“关于”，诊断信息不包含用户名、主机名、序列号、路径、IP 或 PID。
- [ ] `⌘,` 打开设置；本轮只读取设置，不随意覆盖测试机原有偏好。
- [ ] `⌘Q` 正常退出，退出后不残留 Metrilens 进程。

以下项目仅在相关代码发生变化或具备对应条件时执行：

- [ ] 登录启动开关和系统登录项一致。
- [ ] 休眠/唤醒后采样恢复。
- [ ] 接入电源、电池供电和低电量模式分别检查。
- [ ] 偏好损坏恢复和“恢复默认设置”人工路径；执行前先备份测试机偏好。

## 5. 通过与回滚

必须全部满足：

- 自动验证和远端产物校验通过。
- 没有 P0/P1 问题；安装、启动、退出主路径没有 P2 问题。
- 公开发行时匿名下载可用。
- 已执行项目有记录，条件不足的项目明确标为“未执行”，不能写成“通过”。

若失败，保留原始资产和日志，不覆盖已发布资产。修复后提升补丁版本重新发布；不要移动已经公开的 tag。

## 验收记录模板

```text
版本：
提交：
日期：
测试机：macOS / Apple Silicon
ZIP SHA-256：
自动验证：
远端产物：
首次打开：
两分钟功能检查：
条件性检查：
未执行项及原因：
阻断问题：
结论：通过 / 有条件通过 / 不通过
```
