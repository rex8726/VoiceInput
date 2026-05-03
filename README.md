# VoiceInput

一个极简 macOS 语音输入 MVP：按 Option + 1 开始录音，再按 Option + 1 结束录音；应用调用硅基流动语音转文字和文本模型，把口语整理成清晰文本，并自动粘贴到当前输入框，同时保留剪贴板兜底。

## 特性

- 全局快捷键语音输入。
- 语音转文字后自动整理为清晰、结构化文本。
- 去除口水词、补标点、分段，并尽量保留原意。
- 自动粘贴到当前输入框，剪贴板兜底。
- macOS 菜单栏常驻。
- 本地保存最近历史，API Key 存储在 Keychain。

## 当前能力

- 菜单栏常驻应用。
- Option + 1 单击切换录音开始/结束。
- 不再使用 Fn 作为触发键，避免和 macOS 输入法切换冲突。
- 底部悬浮状态组件：正在听、整理中、已输入、处理失败。
- 硅基流动 STT：`POST /v1/audio/transcriptions`。
- 硅基流动 Chat Completions：`POST /v1/chat/completions`。
- 标准整理：补标点、分段、去口水词、去重复、轻微整理语序。
- 自动粘贴到当前输入框。
- 自动复制到剪贴板作为兜底。
- 最近 10 条历史记录。
- API Key 存储在 macOS Keychain。
- 设置页可以测试文本整理模型。
- API Key 输入支持手动粘贴按钮，避免安全输入框焦点问题。
- 菜单栏和设置页显示权限状态。
- 设置页支持开机自启。
- STT 成功但 AI 整理失败时，会复制原始转写，避免内容丢失。

## 运行

构建 App：

```bash
./scripts/build_app.sh
```

打开 App：

```bash
open build/VoiceInput.app
```

运行核心逻辑检查：

```bash
swift run VoiceInputChecks
```

首次使用需要在系统设置里允许：

- 麦克风权限。
- 辅助功能权限，用于自动粘贴。
- 如果 Option + 1 无法全局触发，可能还需要输入监控权限。

## 配置

从菜单栏麦克风图标打开“设置...”：

- Base URL 默认：`https://api.siliconflow.cn/v1`
- 语音转文字模型默认：`FunAudioLLM/SenseVoiceSmall`
- 文本整理模型默认：`Pro/zai-org/GLM-5.1`
- API Key：在设置页填写并保存。
- API 超时默认：45 秒，可在设置页调整。
- 开机自启：在设置页“输入”区域打开，会写入当前用户的 `~/Library/LaunchAgents/cn.local.voiceinput.loginitem.plist`。

不要把 API Key 写进仓库或提交到代码里。

## 失败兜底

- 没有输入框或无法确认当前焦点可编辑时：结果复制到剪贴板。
- 辅助功能权限未开启时：结果复制到剪贴板。
- 语音转文字失败时：不粘贴，显示错误。
- 语音转文字成功但文本整理失败时：复制原始转写，并在历史记录里保留原文。

## 已知限制

- Fn 键会和 macOS 输入法切换冲突，所以不再作为触发键。
- 当前自动粘贴使用剪贴板 + Cmd+V。
- 为了兼容浏览器和聊天软件输入框，自动粘贴会在有辅助功能权限时直接尝试 Cmd+V；如果当前没有输入框，内容仍保留在剪贴板。
- 第一版不保存原始音频，处理完成后删除临时录音文件。
- 第一版没有做翻译、问答、长音频文件转写或会议记录。
- `swift test` 在当前 Command Line Tools 环境里不可用，项目使用 `swift run VoiceInputChecks` 作为轻量回归检查入口。

## License

MIT
