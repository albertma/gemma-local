import Foundation
import MLXLLM
import MLXVLM
import MLXLMCommon
import SwiftUI

// MARK: - 模型定义

struct GemmaModel: Identifiable {
    let id: String
    let name: String
    let huggingFaceId: String
    let type: ModelType

    enum ModelType {
        case llm   // 纯文本
        case vlm   // 多模态 (图片+文本)
    }
}

/// 本地 Gemma 模型推理服务
@MainActor
class LLMService: ObservableObject {

    // MARK: - 可选模型列表

    static let availableModels: [GemmaModel] = [
        GemmaModel(
            id: "gemma3n-e2b-text",
            name: "Gemma 3n E2B 纯文本 (~2GB)",
            huggingFaceId: "mlx-community/gemma-3n-E2B-it-lm-4bit",
            type: .llm
        ),
        GemmaModel(
            id: "gemma3n-e4b-text",
            name: "Gemma 3n E4B 纯文本 (~3GB)",
            huggingFaceId: "mlx-community/gemma-3n-E4B-it-lm-4bit",
            type: .llm
        ),
        GemmaModel(
            id: "gemma3-4b-vlm",
            name: "Gemma 3 4B 多模态 (~3GB)",
            huggingFaceId: "mlx-community/gemma-3-4b-it-qat-4bit",
            type: .vlm
        ),
    ]

    // MARK: - Published State

    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var loadingProgress: String = ""
    @Published var currentOutput: String = ""
    @Published var modelLoaded = false
    @Published var selectedModelIndex = 0
    @Published var downloadProgress: Double = 0

    // MARK: - Private

    private var modelContainer: ModelContainer?

    var selectedModel: GemmaModel {
        Self.availableModels[selectedModelIndex]
    }

    var supportsImages: Bool {
        selectedModel.type == .vlm
    }

    // MARK: - Load Model

    func loadModel() async {
        guard !isLoading else { return }

        isLoading = true
        modelLoaded = false
        loadingProgress = "正在下载并加载模型..."
        downloadProgress = 0

        let model = selectedModel

        do {
            let configuration = ModelConfiguration(id: model.huggingFaceId)

            let factory: any ModelFactory = switch model.type {
            case .llm: LLMModelFactory.shared
            case .vlm: VLMModelFactory.shared
            }

            let container = try await factory.loadContainer(
                configuration: configuration
            ) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted
                    let mb = Double(progress.completedUnitCount) / 1_048_576
                    let totalMb = Double(progress.totalUnitCount) / 1_048_576
                    self.loadingProgress = String(
                        format: "下载中: %.0f / %.0f MB (%.0f%%)",
                        mb, totalMb, progress.fractionCompleted * 100
                    )
                }
            }

            self.modelContainer = container
            self.modelLoaded = true
            self.loadingProgress = "模型加载完成"
        } catch {
            self.loadingProgress = "加载失败: \(error.localizedDescription)"
            print("Model loading error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Unload Model

    func unloadModel() {
        modelContainer = nil
        modelLoaded = false
        loadingProgress = ""
        currentOutput = ""
    }

    // MARK: - Memory Management

    /// 处理内存压力，在收到内存警告或进入后台时调用
    func handleMemoryPressure() {
        // 如果正在生成，不释放模型（避免中断用户操作）
        guard !isGenerating else { return }
        
        // 释放模型以释放内存
        unloadModel()
        loadingProgress = "已释放模型以节省内存"
    }

    // MARK: - Generate (Text Only)

    func generate(prompt: String) async -> String {
        guard let container = modelContainer else {
            return "请先加载模型"
        }

        isGenerating = true
        currentOutput = ""

        do {
            let userInput = UserInput(
                chat: [
                    .user(prompt)
                ]
            )

            let result: String = try await autoreleasepool {
                let stream = try await container.perform { (context: ModelContext) in
                    let lmInput = try await context.processor.prepare(input: userInput)
                    return try MLXLMCommon.generate(
                        input: lmInput,
                        parameters: GenerateParameters(
                            temperature: 0.7,
                            topP: 0.9,
                            maxTokens: 512  // 限制最大输出长度，防止内存溢出
                        ),
                        context: context
                    )
                }

                var fullOutput = ""
                var tokenCount = 0
                let maxTokens = 512
                
                for await generation in stream {
                    switch generation {
                    case .chunk(let text):
                        fullOutput += text
                        tokenCount += 1
                        
                        // 更新UI（限制频率，减少内存压力）
                        if tokenCount % 5 == 0 || tokenCount >= maxTokens {
                            Task { @MainActor in
                                self.currentOutput = fullOutput
                            }
                        }
                        
                        // 达到最大token数时停止
                        if tokenCount >= maxTokens {
                            fullOutput += "\n\n[已达到最大输出长度]"
                            break
                        }
                    case .info:
                        break
                    default:
                        break
                    }
                }
                
                // 最后一次更新UI
                Task { @MainActor in
                    self.currentOutput = fullOutput
                }
                
                return fullOutput
            }

            isGenerating = false
            return result
        } catch {
            isGenerating = false
            let errorMsg = "生成失败: \(error.localizedDescription)"
            currentOutput = errorMsg
            return errorMsg
        }
    }

    // MARK: - Generate (Multimodal: Image + Text)

    func generate(prompt: String, image: UIImage) async -> String {
        guard let container = modelContainer else {
            return "请先加载模型"
        }

        guard supportsImages else {
            return "当前模型不支持图片输入，请选择 Gemma 3 4B 多模态模型"
        }

        isGenerating = true
        currentOutput = ""

        do {
            // 在autoreleasepool中处理，确保内存及时释放
            let result: String = try await autoreleasepool {
                // 缩放图片以减少内存占用（降低分辨率以减少内存使用）
                let resized = resizeImage(image, maxDimension: 224)
                
                // 安全地创建 CIImage，避免强制解包导致崩溃
                guard let ciImage = CIImage(image: resized) else {
                    return "图片处理失败：无法创建 CIImage"
                }

                // 使用正确的 VLM API：UserInput(prompt:images:) 
                // prompt 参数需要是 UserInput.Prompt 类型，使用 .text() 包装
                // 参考：https://github.com/ml-explore/mlx-swift-examples/releases
                let userInput = UserInput(
                    prompt: .text(prompt),
                    images: [.ciImage(ciImage)],
                    processing: .init(resize: CGSize(width: 224, height: 224))
                )

                let stream = try await container.perform { [userInput] (context: ModelContext) in
                    let lmInput = try await context.processor.prepare(input: userInput)
                    return try MLXLMCommon.generate(
                        input: lmInput,
                        parameters: GenerateParameters(
                            temperature: 0.7,
                            topP: 0.9,
                            maxTokens: 256  // 图片模式限制更严格
                        ),
                        context: context
                    )
                }

                var fullOutput = ""
                var tokenCount = 0
                let maxTokens = 256
                
                for await generation in stream {
                    switch generation {
                    case .chunk(let text):
                        fullOutput += text
                        tokenCount += 1
                        
                        // 限制UI更新频率
                        if tokenCount % 3 == 0 || tokenCount >= maxTokens {
                            Task { @MainActor in
                                self.currentOutput = fullOutput
                            }
                        }
                        
                        // 达到最大token数时停止
                        if tokenCount >= maxTokens {
                            fullOutput += "\n\n[已达到最大输出长度]"
                            break
                        }
                    case .info:
                        break
                    default:
                        break
                    }
                }
                
                // 最后一次更新UI
                Task { @MainActor in
                    self.currentOutput = fullOutput
                }
                
                return fullOutput
            }

            isGenerating = false
            return result
        } catch {
            isGenerating = false
            let errorMsg = "生成失败: \(error.localizedDescription)"
            currentOutput = errorMsg
            return errorMsg
        }
    }

    // MARK: - Helpers

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
