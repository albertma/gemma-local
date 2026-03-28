# GemmaLocal

在 iPhone 上本地运行 Google Gemma 大语言模型，支持纯文本对话和图片理解，推理完全离线。

## 功能

- 本地推理，无需服务器
- 纯文本对话（Gemma 3n）
- 图片 + 文本多模态理解（Gemma 3 4B）
- 流式输出，逐字显示
- Markdown 渲染

## 可选模型

| 模型 | 类型 | 大小 | 说明 |
|------|------|------|------|
| Gemma 3n E2B | 纯文本 | ~2GB | 最轻量，速度最快 |
| Gemma 3n E4B | 纯文本 | ~3GB | 质量更高 |
| Gemma 3 4B | 多模态 | ~3GB | 支持图片输入 |

模型首次加载时自动从 HuggingFace 下载并缓存到设备，后续使用无需网络。

## 环境要求

- iOS 17.0+
- Xcode 16.0+
- iPhone 15 Pro 或更新机型（需要足够内存和 Apple Silicon）
- 首次加载需要网络

## 运行

```bash
open GemmaLocal/GemmaLocal.xcodeproj
```

在 Xcode 中选择真机 Target，直接 Build & Run。

> 如需重新生成 `.xcodeproj`（修改了 `project.yml` 之后）：
>
> ```bash
> brew install xcodegen   # 首次需要安装
> cd GemmaLocal && xcodegen generate
> ```

## 项目结构

```
GemmaLocal/
├── project.yml                    # XcodeGen 项目配置
├── Info.plist
├── GemmaLocal.entitlements        # 内存扩展权限
└── Sources/
    ├── App/
    │   └── GemmaLocalApp.swift    # 入口
    ├── Models/
    │   └── ChatMessage.swift      # 消息数据模型
    ├── Services/
    │   └── LLMService.swift       # 模型加载与推理
    └── Views/
        ├── ContentView.swift      # 主界面
        └── ImagePicker.swift      # 相册/相机选择器
```

## 依赖

| 包 | 用途 |
|----|------|
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MLX 推理引擎（含 MLXLLM、MLXVLM、MLXLMCommon），自动传递 mlx-swift 和 swift-transformers |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown 渲染 |

## 使用

1. 启动 App，选择一个模型
2. 点击「加载模型」，等待下载完成
3. 输入文字发送对话
4. 选择多模态模型时，可点击图片按钮附带图片提问
