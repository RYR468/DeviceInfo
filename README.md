# 设备信息 · Action Button 一键启动

按 iPhone 的 **Action Button** 直接打开本 App，查看 **CPU / 内存 / 存储** 占用。

设计目标：**¥0、无需拥有 Mac**——用 GitHub Actions（免费 macOS runner）编译未签名 `.ipa`，再用 Windows 上的 AltStore + 免费 Apple ID 签名装机。

> 仅自用 sideload，不过 App Store 审核，所以可以放心用 Mach 私有 API 取 CPU/系统内存。

---

## 仓库结构

```
project.yml                 XcodeGen 工程描述（你只维护这个，不碰 .xcodeproj）
Sources/
  DeviceInfoApp.swift       @main 入口
  DashboardView.swift       SwiftUI 仪表盘
  SystemMonitor.swift       存储/内存/CPU 取值（Mach）
  Formatter.swift           字节/百分比格式化
.github/workflows/build.yml CI：编译并产出未签名 ipa
```

---

## 1. 编译（push 即可）

```bash
# 在 Windows/iPad 上把代码推到一个【公开】GitHub 仓库（公开仓库 macOS runner 分钟数无限免费）
git init && git add . && git commit -m "init: DeviceInfo"
git remote add origin https://github.com/<你>/DeviceInfo.git
git push -u origin main
```

push 后 GitHub **Actions** 自动跑：`xcodegen generate` → `xcodebuild`（未签名）→ 打包 `DeviceInfo.ipa`。
进仓库的 **Actions → 最新一次运行 → 最底部 Artifacts → DeviceInfo-ipa** 下载。

> ⚠️ 仓库必须是 **public**。私有仓库 macOS 分钟数按 10× 计费。

---

## 2. 装机（Windows + AltStore + 免费 Apple ID）

1. 装 **AltServer for Windows**，并装好依赖：iCloud for Windows、Apple Devices（Apple 新版设备管理）、iTunes 里开启「与此 iPhone 同步 via Wi-Fi」。全部免费。
2. iPhone 用线连一次 Windows 建立信任，之后走 Wi-Fi。
3. 下载上一步的 `DeviceInfo.ipa`。
4. AltStore 里 **+** 选 `DeviceInfo.ipa`，登录你的**免费 Apple ID**（需已开双重认证）→ 自动签名装机。
5. iPhone：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。

**续签**：免费 Apple ID 证书 7 天过期。AltStore 在「iPhone 与 AltServer 同一 Wi-Fi + AltServer 开着」时后台自动续签；不行就每周点一次手动 refresh。
（免费账号硬限制：每台设备最多 3 个 sideload App；本 App 只占 1 个。）

---

## 3. 接管 Action Button（iPhone 上操作）

不用 App Intents（sideload 下会失效），用「打开 App」快捷指令——对所有已装 App 生效。

**方式 A（首选）**
1. 「快捷指令」App → 新建快捷指令。
2. 加动作「打开 App」→ 选「设备信息」。
3. 设置 → Action Button → 快捷指令 → 选刚才那条。

**方式 B（兜底，若 A 的 App 列表里没出现）**
1. 快捷指令加动作「打开 URL」= `deviceinfo://`。
2. Action Button 绑这条快捷指令。（URL Scheme 已在 `project.yml` 注册。）

---

## 数据来源与精度

| 数据 | 来源 | 精度 |
|---|---|---|
| 存储 | `URLResourceValues`（公开 API） | ✅ 准确，与系统设置一致 |
| 内存 总量 | `ProcessInfo.physicalMemory` | ✅ 准确 |
| 内存 已用/空闲 | Mach `host_statistics64`（active+wired+compressed / free+inactive） | ⚠️ 近似系统级占用 |
| 本 App 可申请内存 | `os_proc_available_memory()`（公开） | 反映 App 预算，≠系统空闲 RAM |
| CPU | Mach `host_processor_info` 两次采样算 delta | ⚠️ 尽力值，语义不等于 Activity Monitor |

---

## 已知限制

- **CPU 是尽力值**：偶发跳变正常。
- **7 天重签**：免费 Apple ID 不可绕开；想彻底免烦可日后升 $99/年（续签延到 365 天）。
- **iOS 版本漂移**：Mach `host_processor_info` 在未来 iOS 有被收紧的小风险；某次系统升级后若 CPU 恒为 0，回来调代码。
- **机型名映射不全**：`SystemMonitor.swift` 里的 `machineNames` 只列了带 Action Button 的几款；新机型会显示原始代号（如 `iPhone17,5`），可自行补。
