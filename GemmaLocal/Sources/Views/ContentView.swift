import SwiftUI
import MarkdownUI

struct ContentView: View {
    @EnvironmentObject var llmService: LLMService

    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showingSourceSelector = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !llmService.modelLoaded {
                    modelSetupView
                } else {
                    chatView
                }
            }
            .navigationTitle("Gemma Local")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if llmService.modelLoaded {
                        Menu {
                            Text(llmService.selectedModel.name)
                            Divider()
                            Button(role: .destructive) {
                                llmService.unloadModel()
                                messages.removeAll()
                            } label: {
                                Label("卸载模型", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Model Setup View

    private var modelSetupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.gradient)

                Text("Gemma 本地 AI")
                    .font(.title2.bold())

                Text("在你的 iPhone 上离线运行 Google Gemma 模型\n支持文本对话和图片理解")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // 模型选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择模型")
                        .font(.headline)

                    ForEach(Array(LLMService.availableModels.enumerated()), id: \.element.id) { index, model in
                        ModelCard(
                            model: model,
                            isSelected: llmService.selectedModelIndex == index
                        ) {
                            llmService.selectedModelIndex = index
                        }
                    }
                }
                .padding(.horizontal, 24)

                // 加载按钮/进度
                if llmService.isLoading {
                    VStack(spacing: 12) {
                        ProgressView(value: llmService.downloadProgress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 48)

                        Text(llmService.loadingProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        ProgressView()
                            .scaleEffect(0.8)
                    }
                } else {
                    Button {
                        Task { await llmService.loadModel() }
                    } label: {
                        Label("加载模型", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 48)

                    if llmService.loadingProgress.contains("失败") {
                        Text(llmService.loadingProgress)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                }

                Text("首次加载需要下载模型文件，请确保网络通畅\niPhone 15 Pro 及以上设备推荐")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 40)
            }
        }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 提示信息
                        if messages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.largeTitle)
                                    .foregroundStyle(.purple.gradient)
                                    .padding(.top, 60)

                                Text("模型已就绪")
                                    .font(.headline)

                                if llmService.supportsImages {
                                    Text("支持文本对话和图片理解\n试试发一张图片问问题吧")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("当前为纯文本模型\n发送消息开始对话")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming output
                        if llmService.isGenerating && !llmService.currentOutput.isEmpty {
                            MessageBubble(
                                message: ChatMessage(role: .assistant, text: llmService.currentOutput)
                            )
                            .id("streaming")
                        }

                        // Loading indicator
                        if llmService.isGenerating && llmService.currentOutput.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("思考中...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: llmService.currentOutput) {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Selected image preview
            if let image = selectedImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading) {
                        Text("已选择图片")
                            .font(.caption.bold())
                        if !llmService.supportsImages {
                            Text("当前模型不支持图片")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer()

                    Button {
                        selectedImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
            }

            // Input bar
            inputBar
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 图片按钮
            Button {
                showingSourceSelector = true
            } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.title3)
                    .foregroundColor(llmService.supportsImages ? .blue : .gray)
            }
            .disabled(llmService.isGenerating)
            .confirmationDialog("选择图片来源", isPresented: $showingSourceSelector) {
                Button("相册") {
                    imagePickerSource = .photoLibrary
                    showingImagePicker = true
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("相机") {
                        imagePickerSource = .camera
                        showingImagePicker = true
                    }
                }
            }

            // 文本输入
            TextField("输入消息...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // 发送按钮
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage, sourceType: imagePickerSource)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !llmService.isGenerating
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let image = selectedImage
        let userMessage = ChatMessage(role: .user, text: text, image: image)
        messages.append(userMessage)

        inputText = ""
        selectedImage = nil

        Task {
            let response: String
            if let image, llmService.supportsImages {
                response = await llmService.generate(prompt: text, image: image)
            } else {
                response = await llmService.generate(prompt: text)
            }

            let assistantMessage = ChatMessage(role: .assistant, text: response)
            messages.append(assistantMessage)
        }
    }
}

// MARK: - Model Card

struct ModelCard: View {
    let model: GemmaModel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Image(systemName: model.type == .vlm ? "photo.badge.checkmark" : "text.bubble")
                            .font(.caption2)
                        Text(model.type == .vlm ? "支持图片+文本" : "仅文本")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : .clear, lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.purple)
                    .padding(.top, 4)
            }

            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if message.role == .assistant {
                    Markdown(message.text)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Text(message.text)
                        .padding(12)
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LLMService())
}
