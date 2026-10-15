# 从源码构建

普通使用请下载 Releases 的完整安装包；以下仅用于修改主题和构建。

需要 Windows x64、Python 3，以及 .NET Framework C# 编译器（`%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`）。

1. 从 [Codex Dream Skin v1.5.20](https://github.com/Fei-Away/Codex-Dream-Skin/releases/tag/v1.5.20) 下载 `CodexDreamSkin-Setup-v1.5.20.exe` 和该版本源码压缩包。
2. 解压上游源码，保留其 `windows` 文件夹。
3. 先检查，再构建。将下面的示例路径替换为实际文件路径：

```powershell
python build.py --upstream "C:\Projects\Codex-Dream-Skin-1.5.20" --installer "C:\Downloads\CodexDreamSkin-Setup-v1.5.20.exe" --check-only
python build.py --upstream "C:\Projects\Codex-Dream-Skin-1.5.20" --installer "C:\Downloads\CodexDreamSkin-Setup-v1.5.20.exe"
```

构建会检查固定安装器和上游文件的 SHA-256，编译安装、卸载和内部日常启动三个 Windows 入口，生成内部校验清单与安装 ZIP。不会运行安装器、关闭客户端或应用主题。输出到 `dist`；已有同名输出会停止，不自动删除。

仓库的文件映射：

| 根目录文件 | 发布包中的位置 |
| --- | --- |
| `Launcher.cs` | 编译成最外层两个 EXE 与 files/ChatGPT-NASA.exe |
| 五个包管理 `.ps1` 与 `使用说明.txt` | `files/` |
| `lone-star-adapter.mjs`、`lone-star-style.mjs`、`manage-lone-star.ps1`、哈希清单 | `files/.support/` |
| `lone-star-runtime-api.mjs` | 固定上游运行器的 `windows/scripts/` |
| `theme.json`、`theme.css`、`background.png` | `files/lone-star-theme/` |
| `NASA-Punk-Theme.zip` | 完整发布包使用的内层主题包 |

内部路径保留开发时期的 `lone-star` 命名以保证脚本一致；当前视觉方向是 NASA-punk。修改三个主题源文件时，需要同时更新内层主题 ZIP 及管理脚本中的预期哈希。当前构建器对这两者进行一致性检查，并不会静默修改它们。

重新构建的 ZIP 时间戳和可执行文件元数据可能与发布资产不同，请使用新输出的 SHA-256；仓库 `SHA256SUMS.txt` 对应当前本地测试安装包。

## 隔离链路回归

需要已构建的完整文件夹和由 OpenJS Foundation 签名的 Node.js 22+。测试副本及临时用户配置放在新目录，建议选择短路径以适配 Windows PowerShell 5.1 的路径长度限制。

```powershell
python test_lifecycle.py --package "C:/Build/NASA-Punk-Windows-v0.7.3-beta" --output "C:/Temp/nasa-test-01" --node "C:/Tools/node.exe"
```

测试只修改新建的副本与隔离配置，使用真实上游导入、签名校验、指纹、快捷方式、选择性恢复和清理。实际客户端启动和运行器安装边界使用替代操作；不会打开、关闭或重启真实 ChatGPT。它不能代替真实客户端、电脑重启和干净电脑验收。

## 统一加载与快速复用回归

`build.py` 从固定上游启动/验证脚本生成私有 `start-nasa-session.ps1` 和 `verify-nasa-session.ps1`，把 injector 指向本项目适配副本、Node 指向已安装的签名运行时，并从完整的已安装引擎初始化默认主题。上游原文件保持原样。固定 NASA 样式来自 `lone-star-style.mjs`，与引擎样式共享生命周期。

```powershell
python test_startup_validation.py
node test_unified_runtime.mjs --upstream "C:/Projects/Codex-Dream-Skin-1.5.20"
python test_startup_reuse.py
python test_startup_bootstrap.py --upstream "C:/Projects/Codex-Dream-Skin-1.5.20" --node "C:/Tools/node.exe"
```

统一样式测试使用固定上游 renderer 的隔离 DOM，检查样式内容、反复加载、切换和清理；快速复用测试隔离操作系统和窗口操作边界。它们不会启动或关闭真实客户端。实际 Node 需为 22+；生命周期测试额外验证 OpenJS 签名。
