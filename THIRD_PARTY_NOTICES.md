# 第三方依赖

本主题的桌面换肤运行器来自 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin)，固定版本 **1.5.20**。上游使用 MIT License；完整许可保留于 [Codex-Dream-Skin-LICENSE.txt](Codex-Dream-Skin-LICENSE.txt) 和发布包的 `files/licenses/`。

上游许可中的原始署名：`Copyright (c) 2026 Codex Dream Skin Studio contributors`。完整保留版权声明、许可正文与免责声明，不将第三方代码标为本项目原创。

## 使用方式与改动范围

| 组件 | 来源与处理方式 |
| --- | --- |
| 发布包内固定版本 Windows 安装器 | 来自上游 v1.5.20 发布资产，保留原二进制；以 SHA-256 固定版本 |
| 运行器的 `windows/assets/` 与 `windows/scripts/` 必要文件 | 从上游 v1.5.20 选择引用，文件内容保持原样；对应清单为 `selected-runtime-hashes.json` |
| `lone-star-runtime-api.mjs` | 复制上游 `windows/scripts/injector.mjs`，增加具名导出、固定 NASA 样式的统一 payload 和只读健康检查；保留上游连接、注入、校验及清理逻辑；沿用上游 MIT 许可 |
| 生成的 `start-nasa-session.ps1` / `verify-nasa-session.ps1` | 从上游固定启动/验证脚本生成，适配 injector、已安装的签名 Node 路径，以及完整引擎的默认主题初始化路径；沿用上游 MIT 许可 |
| `lone-star-style.mjs`、`lone-star-adapter.mjs`、`manage-lone-star.ps1` | 本项目的样式适配和运行管理代码，调用上游运行器接口及 PowerShell 辅助函数；不将被调用的上游能力标为自研引擎 |
| `Launcher.cs`、五个安装包管理脚本、`build.py` | 本项目编写的启动入口、安装/卸载包装及构建逻辑 |
| 主题 CSS、配置、底图 | 本项目制作的 NASA-punk 外观文件，不是 NASA 官方设计资产 |

固定安装器 SHA-256：`2b13c6816c30ea4000aaa0dd7ef9a4935508816192124e7b87e3b29759c1f8b3`。

## 上游安装器携带的组件

以下依赖已包含在未修改的 Codex Dream Skin 安装器中，不是本项目自行创作的内容：

- **Node.js v22.23.1 win-x64**：上游安装器包含固定官方归档中的 `node.exe` 和完整 `LICENSE`；安装后许可位于运行器的 `runtime/node/LICENSE`。Node.js 及其依赖适用各自许可，不能只用本仓库的 MIT 文本概括。项目源码也调用系统 .NET Framework、Windows PowerShell 与 Node.js 内置模块。
- **Inno Setup 简体中文消息文件**：上游按 Inno Setup `is-6_7_1` 固定版本引用，原样保留。上游署名为 Zhenghan Yang，适用 Inno Setup License；本仓库附有完整 [Inno-Setup-License.txt](Inno-Setup-License.txt)。
- **Gothic Void Crusade 默认底图**：上游安装器的 `preset-gothic-void-crusade/background.jpg` 由 [seansong-ideogram](https://github.com/seansong-ideogram) 通过上游 [PR #134](https://github.com/Fei-Away/Codex-Dream-Skin/pull/134) 贡献，按上游通知获准随公开安装器分发。该图片属于上游自带预设，不是本项目的 NASA-punk 主题底图。

完整上游通知原文另存为 [Codex-Dream-Skin-NOTICE.md](Codex-Dream-Skin-NOTICE.md)。源码中的运行器文件哈希清单用于完整性校验，不代替完整依赖与许可说明。

`lone-star-runtime-api.mjs` 是基于上游运行器脚本的适配副本，保留上游许可。发布包含上游 Windows 安装器与必要的运行器文件；源码仓库不上传安装器二进制。

NASA-punk 是本项目的设计参考。这里不分发 NASA 官方标志、不提供商业字体文件，也不代表 NASA 或 OpenAI 的官方支持。

第三方组件及其依赖的权利归各自作者，保留上游所提供的许可。当前尚未为项目自有文件指定独立开源许可；上游 MIT 许可仅覆盖其适用的第三方文件和修改副本。
