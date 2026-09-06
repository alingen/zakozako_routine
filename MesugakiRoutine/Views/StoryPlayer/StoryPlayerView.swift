import SwiftUI

/// Story Playerエンジンの状態を、描画層へ渡すための読み取り専用境界。
/// Core側のObservableなplayerは、このprotocolへ直接準拠するかSnapshotへ変換できる。
protocol StoryPlayerViewInput {
    var title: String { get }
    var scenarioType: StoryScenarioType { get }
    var currentNode: StoryNode? { get }
    var currentMode: StoryScreenMode { get }
    var visibleChatNodes: [StoryNode] { get }
    var backgroundAssetID: String? { get }
    var portraitAssetID: String? { get }
    var cgAssetID: String? { get }
    var availableChoices: [StoryChoice] { get }
    var isTyping: Bool { get }
    var isModalPresented: Bool { get }
    var isCompleted: Bool { get }
    var recoverableError: String? { get }
}

/// Core player未接続時やPreview、テストでも使える値型adapter。
struct StoryPlayerViewSnapshot: StoryPlayerViewInput {
    let title: String
    let scenarioType: StoryScenarioType
    let currentNode: StoryNode?
    let currentMode: StoryScreenMode
    let visibleChatNodes: [StoryNode]
    let backgroundAssetID: String?
    let portraitAssetID: String?
    let cgAssetID: String?
    let availableChoices: [StoryChoice]
    let isTyping: Bool
    let isModalPresented: Bool
    let isCompleted: Bool
    let recoverableError: String?

    init(
        title: String,
        scenarioType: StoryScenarioType,
        currentNode: StoryNode?,
        currentMode: StoryScreenMode = .adv,
        visibleChatNodes: [StoryNode] = [],
        backgroundAssetID: String? = nil,
        portraitAssetID: String? = nil,
        cgAssetID: String? = nil,
        availableChoices: [StoryChoice] = [],
        isTyping: Bool = false,
        isModalPresented: Bool = false,
        isCompleted: Bool = false,
        recoverableError: String? = nil
    ) {
        self.title = title
        self.scenarioType = scenarioType
        self.currentNode = currentNode
        self.currentMode = currentMode
        self.visibleChatNodes = visibleChatNodes
        self.backgroundAssetID = backgroundAssetID
        self.portraitAssetID = portraitAssetID
        self.cgAssetID = cgAssetID
        self.availableChoices = availableChoices
        self.isTyping = isTyping
        self.isModalPresented = isModalPresented
        self.isCompleted = isCompleted
        self.recoverableError = recoverableError
    }
}

/// fullScreenCoverでの表示を前提とするStory Playerの統合画面。
/// シナリオ進行や永続化は行わず、すべてcallbackを通じてCoreへ委譲する。
struct StoryPlayerView: View {
    let input: any StoryPlayerViewInput
    let onAdvance: () -> Void
    let onChoice: (StoryChoice) -> Void
    let onDismissModal: () -> Void
    let onRestart: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @State private var isShowingRestartConfirmation = false

    var body: some View {
        ZStack {
            playerContent
                .ignoresSafeArea(
                    edges: input.currentMode == .chat ? [.horizontal, .bottom] : .all
                )

            VStack(spacing: 10) {
                topBar

                if let error = input.recoverableError, !error.isEmpty {
                    recoverableErrorBanner(error)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .background(AppColor.background.ignoresSafeArea())
        .confirmationDialog(
            input.isCompleted ? "このストーリーをもう一度読みますか？" : "最初から読み直しますか？",
            isPresented: $isShowingRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button("最初から読む") { onRestart() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存済みの途中位置はリセットされます。読了状態と思い出は保持されます。")
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        if input.isCompleted {
            completionView
        } else if let node = input.currentNode {
            switch input.currentMode {
            case .adv:
                ADVStoryRenderer(
                    node: node,
                    scenarioType: input.scenarioType,
                    backgroundAssetID: input.backgroundAssetID,
                    portraitAssetID: input.portraitAssetID,
                    cgAssetID: input.cgAssetID,
                    choices: input.availableChoices,
                    isModalPresented: input.isModalPresented,
                    onAdvance: onAdvance,
                    onSelectChoice: onChoice,
                    onDismissModal: onDismissModal
                )
            case .chat:
                ChatStoryRenderer(
                    node: node,
                    scenarioType: input.scenarioType,
                    visibleNodes: input.visibleChatNodes,
                    backgroundAssetID: input.backgroundAssetID,
                    portraitAssetID: input.portraitAssetID,
                    cgAssetID: input.cgAssetID,
                    choices: input.availableChoices,
                    isTyping: input.isTyping,
                    isModalPresented: input.isModalPresented,
                    onAdvance: onAdvance,
                    onSelectChoice: onChoice,
                    onDismissModal: onDismissModal
                )
            case .call:
                CallStoryRenderer(
                    node: node,
                    backgroundAssetID: input.backgroundAssetID,
                    portraitAssetID: input.portraitAssetID,
                    cgAssetID: input.cgAssetID,
                    choices: input.availableChoices,
                    isModalPresented: input.isModalPresented,
                    onAdvance: onAdvance,
                    onSelectChoice: onChoice,
                    onDismissModal: onDismissModal
                )
            case .unknown(let rawValue):
                unknownModeView(node: node, modeName: rawValue)
            }
        } else {
            unavailableStateView
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if input.scenarioType != .smallEvent {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.bold())
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(AppColor.text)
                .accessibilityLabel("ストーリーを閉じる")
            }

            Text(input.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Menu {
                Button {
                    isShowingRestartConfirmation = true
                } label: {
                    Label(input.isCompleted ? "もう一度読む" : "最初から読み直す", systemImage: "arrow.counterclockwise")
                }
                if input.scenarioType == .smallEvent, !input.isCompleted {
                    Button(action: onSkip) {
                        Label("スキップ", systemImage: "forward.end.fill")
                    }
                } else {
                    Button(action: onClose) {
                        Label("閉じる", systemImage: "xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.bold())
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(AppColor.text)
            .accessibilityLabel("ストーリーメニュー")
        }
    }

    private func recoverableErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppColor.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.warning.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("注意。\(message)")
    }

    private var completionView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(AppColor.primary)
                .frame(width: 112, height: 112)
                .background(AppColor.primarySoft, in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("読了")
                    .font(.title.bold())
                    .foregroundStyle(AppColor.text)
                Text(input.title)
                    .font(.headline)
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                isShowingRestartConfirmation = true
            } label: {
                Label("もう一度読む", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppColor.primary)

            Button("閉じる", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .background(AppColor.background)
        .accessibilityElement(children: .contain)
    }

    private func unknownModeView(node: StoryNode, modeName: String) -> some View {
        ZStack(alignment: .top) {
            ADVStoryRenderer(
                node: node,
                scenarioType: input.scenarioType,
                backgroundAssetID: input.backgroundAssetID,
                portraitAssetID: input.portraitAssetID,
                cgAssetID: input.cgAssetID,
                choices: input.availableChoices,
                isModalPresented: input.isModalPresented,
                onAdvance: onAdvance,
                onSelectChoice: onChoice,
                onDismissModal: onDismissModal
            )

            Text("未対応の画面モード: \(modeName)")
                .font(.caption.monospaced())
                .foregroundStyle(AppColor.warning)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColor.surface.opacity(0.96), in: Capsule())
                .padding(.top, 58)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
    }

    private var unavailableStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(AppColor.muted)
            Text("表示できるシーンがありません")
                .font(.headline)
                .foregroundStyle(AppColor.text)
            if let error = input.recoverableError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
            }
            Button("最初から読み直す") {
                isShowingRestartConfirmation = true
            }
            .buttonStyle(.bordered)
            .tint(AppColor.primary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
    }
}
