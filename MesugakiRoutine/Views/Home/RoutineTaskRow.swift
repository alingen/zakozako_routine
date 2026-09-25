import SwiftUI

/// Home の「今日の約束」1件を表示する、拡張可能な横長カード。
/// 編集・タイマー・完了は、それぞれ独立したタップ領域として扱う。
struct RoutineTaskRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let iconName: String?
    let cueText: String?
    let streakText: String
    let hasStreak: Bool
    let progressText: String?
    let progressFraction: Double
    let progressCount: Int
    let progressTarget: Int
    let timerStatusText: String?
    let timerTargetDurationMinutes: Int?
    let isTimerActive: Bool
    let isCompleted: Bool
    let isHighlighted: Bool
    let allowsEditing: Bool
    let highlightsDeferredReport: Bool
    let completionActionTrigger: Int
    let reportsCompletionButtonFrame: Bool
    let onEdit: () -> Void
    let onStartTimer: () -> Void
    let onAdvance: () -> Bool
    let onUndoCompletion: () -> Bool
    let onCompletionButtonFrameChange: (CGRect?) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isHighlighted ? AppColor.primary : AppColor.border.opacity(0.72),
                    lineWidth: isHighlighted ? 2.5 : 1
                )
        }
        .shadow(
            color: isHighlighted ? AppColor.primary.opacity(0.16) : AppColor.text.opacity(0.035),
            radius: isHighlighted ? 12 : 7,
            y: isHighlighted ? 4 : 3
        )
        .animation(.easeInOut(duration: 0.2), value: isCompleted)
        .accessibilityElement(children: .contain)
        .onPreferenceChange(RoutineCompletionButtonFramePreferenceKey.self) { frame in
            guard reportsCompletionButtonFrame else { return }
            onCompletionButtonFrameChange(frame)
        }
        .onDisappear {
            guard reportsCompletionButtonFrame else { return }
            onCompletionButtonFrameChange(nil)
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 12) {
            taskDetails
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingControls
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            taskDetails
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                trailingControls
            }
        }
    }

    @ViewBuilder
    private var taskDetails: some View {
        if allowsEditing {
            Button(action: onEdit) {
                taskSummary
            }
            .buttonStyle(RoutineRowPressStyle())
            .accessibilityLabel(taskAccessibilityLabel)
            .accessibilityHint("タップして内容を編集")
        } else {
            taskSummary
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(taskAccessibilityLabel)
                .accessibilityHint("右側の丸をタップして達成を報告")
        }
    }

    private var taskSummary: some View {
        HStack(spacing: 12) {
            // 途中は Primary で満ちていき、達成したら「達成」を表す Purple に変わる。
            RoutineProgressPie(
                progress: progressFraction,
                size: 52,
                tint: isCompleted ? AppColor.secondary : AppColor.primary,
                centerSystemImage: iconName ?? "checklist"
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let cueText, !cueText.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(cueText)
                    }
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    StreakText(text: streakText, isActive: hasStreak)

                    if let progressText {
                        Text("・ \(progressText)")
                            .foregroundStyle(AppColor.muted)
                    }
                }
                .font(.caption)

                if let timerStatusText {
                    Text(timerStatusText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppColor.primary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var taskAccessibilityLabel: String {
        [title, cueText, streakText, progressText]
            .compactMap { $0 }
            .joined(separator: "、")
    }

    private var trailingControls: some View {
        HStack(spacing: 8) {
            if let timerTargetDurationMinutes, !isCompleted {
                Button(action: onStartTimer) {
                    Image(systemName: isTimerActive ? "clock.fill" : "clock")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isTimerActive ? Color.white : AppColor.primary)
                        .frame(width: 46, height: 46)
                        .background(
                            isTimerActive ? AppColor.primary : AppColor.primarySoft,
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    isTimerActive ? AppColor.primary : AppColor.border,
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(RoutineRowPressStyle())
                .accessibilityLabel("\(title)のタイマー")
                .accessibilityValue(isTimerActive ? "動作中" : "\(timerTargetDurationMinutes)分")
                .accessibilityHint(
                    isTimerActive
                        ? "タップして動作中のタイマーを表示"
                        : "タップしてタイマーを開始"
                )
            }

            RoutineCompletionButton(
                title: title,
                isCompleted: isCompleted,
                progressCount: progressCount,
                progressTarget: progressTarget,
                highlightsDeferredReport: highlightsDeferredReport,
                externalActionTrigger: completionActionTrigger,
                reportsFrame: reportsCompletionButtonFrame,
                onAdvance: onAdvance,
                onUndoCompletion: onUndoCompletion
            )
        }
    }
}

/// 「やらないこと」を「今日の約束」と同じカード骨格で表示する。
/// カード本体は編集、右端の丸ボタンは危機／失敗メニュー（または権限再設定）を開く。
struct BlockedBehaviorTaskRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let iconName: String?
    let statusText: String
    let statusColor: Color
    /// 連続で守れている日数を表示しているとき true。炎アイコン付きで表示する。
    let hasStreak: Bool
    let detailText: String?
    /// 現在の期間に残っている回数の割合。1から始まり、失敗を記録するたびに減る。
    let progressFraction: Double
    let isFailed: Bool
    let needsRepair: Bool
    let onEdit: () -> Void
    let onAction: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColor.border.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: AppColor.text.opacity(0.035), radius: 7, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var regularLayout: some View {
        HStack(spacing: 12) {
            editButton
                .frame(maxWidth: .infinity, alignment: .leading)
            stateButton
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            editButton
            HStack {
                Spacer(minLength: 0)
                stateButton
            }
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            summary
                .contentShape(Rectangle())
        }
        .buttonStyle(RoutineRowPressStyle())
        .accessibilityLabel([title, statusText, detailText].compactMap { $0 }.joined(separator: "、"))
        .accessibilityHint("タップして内容を編集")
    }

    private var summary: some View {
        HStack(spacing: 12) {
            summaryIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    if hasStreak {
                        StreakText(text: statusText, isActive: true)
                    } else {
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }
                }
                .font(.caption)

                if let detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    @ViewBuilder
    private var summaryIcon: some View {
        if needsRepair {
            Image(systemName: iconName ?? "hand.raised")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(AppColor.error)
                .frame(width: 52, height: 52)
                .background(AppColor.error.opacity(0.12), in: Circle())
        } else {
            BlockedBehaviorRemainingRing(
                remainingFraction: progressFraction,
                isFailed: isFailed,
                systemImage: iconName ?? "hand.raised"
            )
        }
    }

    /// 約束の完了ボタン(赤い塗り)と区別するため、メニューは白地＋枠線の控えめな見た目にする。
    private var stateButton: some View {
        Button(action: onAction) {
            ZStack {
                Circle()
                    .fill(AppColor.surface)

                Circle()
                    .stroke(
                        needsRepair ? AppColor.error : AppColor.border,
                        lineWidth: isFailed ? 0 : 2.5
                    )

                Image(systemName: stateIconName)
                    .font(.system(size: isFailed ? 32 : 19, weight: .bold))
                    .foregroundStyle(stateIconColor)
            }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
        }
        .buttonStyle(RoutineCompletionPressStyle())
        .accessibilityLabel(actionAccessibilityLabel)
        .accessibilityHint(needsRepair ? "タップして許可を確認" : "タップして選択肢を表示")
    }

    private var stateIconName: String {
        if isFailed { return "nosign" }
        if needsRepair { return "arrow.clockwise" }
        return "ellipsis"
    }

    private var stateIconColor: Color {
        if needsRepair { return AppColor.error }
        if isFailed { return AppColor.primary }
        return AppColor.muted
    }

    private var actionAccessibilityLabel: String {
        if needsRepair { return "\(title)のスクリーンタイムを再設定" }
        if isFailed { return "\(title)は失敗" }
        return "\(title)の選択肢"
    }
}

/// 連続記録の表示。文字は読みやすさのため本文色にし、
/// 「達成」を表すブランドの Yellow は炎アイコン(飾り)に持たせる。
private struct StreakText: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isActive {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppColor.accent)
                    .accessibilityHidden(true)
            }
            Text(text)
                .foregroundStyle(isActive ? AppColor.text : AppColor.muted)
        }
    }
}

/// 「やらないこと」の残り回数。約束の円(塗りつぶし＝達成)と混同しないよう、
/// 薄い地の上に残り割合を線で示し、アイコンは常に色付きのままにする。
private struct BlockedBehaviorRemainingRing: View {
    let remainingFraction: Double
    let isFailed: Bool
    let systemImage: String

    private let size: CGFloat = 52
    private let lineWidth: CGFloat = 3.5

    private var clamped: Double { min(max(remainingFraction, 0), 1) }
    private var tint: Color { isFailed ? AppColor.muted : AppColor.primary }

    var body: some View {
        ZStack {
            Circle()
                .fill(isFailed ? AppColor.muted.opacity(0.12) : AppColor.primarySoft)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: clamped)
        .accessibilityHidden(true)
    }
}

/// 完了操作だけを担当する丸ボタン。約0.4秒で押下→塗り→チェックを表現する。
private struct RoutineCompletionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let isCompleted: Bool
    let progressCount: Int
    let progressTarget: Int
    let highlightsDeferredReport: Bool
    let externalActionTrigger: Int
    let reportsFrame: Bool
    let onAdvance: () -> Bool
    let onUndoCompletion: () -> Bool

    @State private var fillProgress: CGFloat = 0
    @State private var showsCheckmark = false
    @State private var isAnimating = false
    /// いま再生中のタップで目標に届くか。タップ開始時に決め、演出の途中で変えない。
    @State private var currentTapCompletesTarget = false
    @State private var successFeedbackTrigger = 0
    @State private var undoFeedbackTrigger = 0
    @State private var completionTask: Task<Void, Never>?

    private var displayedFillProgress: CGFloat {
        isCompleted ? 1 : fillProgress
    }

    private var displaysCheckmark: Bool {
        isCompleted || showsCheckmark
    }

    private var completesWithNextTap: Bool {
        progressCount + 1 >= max(progressTarget, 1)
    }

    /// 達成済み、または目標に届くタップの演出中は「達成」を表す Purple。
    /// 回数が残るタップの一瞬の塗りは Primary のまま
    /// (記録後に回数が増えても、そのタップの演出の色は変えない)。
    private var fillColor: Color {
        isCompleted || (isAnimating && currentTapCompletesTarget)
            ? AppColor.secondary
            : AppColor.primary
    }

    var body: some View {
        Button(action: toggleCompletion) {
            ZStack {
                Circle()
                    .fill(AppColor.surface)

                Circle()
                    .fill(fillColor)
                    .scaleEffect(reduceMotion ? 1 : displayedFillProgress)
                    .opacity(displayedFillProgress)

                Circle()
                    .stroke(
                        displayedFillProgress > 0 ? fillColor : AppColor.border,
                        lineWidth: 2.5
                    )

                if displaysCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.65).combined(with: .opacity)
                        )
                }
            }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
            .overlay {
                if highlightsDeferredReport && !isCompleted {
                    DeferredReportRing()
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(RoutineCompletionPressStyle())
        .disabled(isAnimating)
        .background {
            if reportsFrame {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RoutineCompletionButtonFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            }
        }
        .accessibilityLabel(isCompleted ? "\(title)を未完了に戻す" : "\(title)を1回報告")
        .accessibilityValue(
            isCompleted
                ? "達成済み"
                : "\(min(max(progressCount, 0), max(progressTarget, 1))) / \(max(progressTarget, 1))回"
        )
        .accessibilityHint(isCompleted ? "タップして最後の報告を取り消す" : "タップして実行回数を1回増やす")
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .sensoryFeedback(.selection, trigger: undoFeedbackTrigger)
        .onAppear {
            fillProgress = isCompleted ? 1 : 0
            showsCheckmark = isCompleted
        }
        .onChange(of: isCompleted) { _, newValue in
            guard !isAnimating else { return }
            showsCheckmark = newValue
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.2)) {
                fillProgress = newValue ? 1 : 0
            }
        }
        .onChange(of: externalActionTrigger) { oldValue, newValue in
            guard reportsFrame, newValue != oldValue else { return }
            toggleCompletion()
        }
        .onDisappear {
            completionTask?.cancel()
        }
    }

    private func toggleCompletion() {
        completionTask?.cancel()

        if isCompleted {
            guard onUndoCompletion() else { return }
            showsCheckmark = false
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.2)) {
                fillProgress = 0
            }
            undoFeedbackTrigger += 1
            return
        }

        guard !isAnimating else { return }
        currentTapCompletesTarget = completesWithNextTap
        isAnimating = true
        fillProgress = 0
        showsCheckmark = false

        let fillDuration = reduceMotion ? 0.08 : 0.22
        let fillDurationMilliseconds = reduceMotion ? 80 : 220
        withAnimation(.easeOut(duration: fillDuration)) {
            fillProgress = 1
        }

        completionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(fillDurationMilliseconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            if onAdvance() {
                withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) {
                    showsCheckmark = true
                }
                successFeedbackTrigger += 1

                if !currentTapCompletesTarget {
                    do {
                        try await Task.sleep(for: .milliseconds(reduceMotion ? 140 : 240))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.16)) {
                        showsCheckmark = false
                        fillProgress = 0
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    fillProgress = 0
                }
            }
            isAnimating = false
            completionTask = nil
        }
    }
}

/// 「あとでやる」の後も、実際の報告ボタンだけを静かに示す。
private struct DeferredReportRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .stroke(AppColor.primary, lineWidth: 3)
            .frame(width: 58, height: 58)
            .opacity(reduceMotion || !isDimmed ? 1 : 0.28)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

private struct RoutineCompletionButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

struct AddRoutineTaskRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 52, height: 52)
                    .background(AppColor.primarySoft, in: Circle())

                Text("約束を追加")
                    .font(.headline)
                    .foregroundStyle(AppColor.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColor.border.opacity(0.72), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(RoutineRowPressStyle())
        .accessibilityHint("新しい約束を作成")
    }
}

struct AddBlockedBehaviorTaskRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 52, height: 52)
                    .background(AppColor.primarySoft, in: Circle())

                Text("やらないことを決める")
                    .font(.headline)
                    .foregroundStyle(AppColor.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColor.border.opacity(0.72), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(RoutineRowPressStyle())
        .accessibilityHint("新しいやらないことを設定")
    }
}

private struct RoutineRowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct RoutineCompletionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension View {
    /// 今日の約束カードを、List の標準背景・区切り線から独立させる。
    func routineListRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#Preview {
    VStack(spacing: 12) {
        RoutineTaskRow(
            title: "10分勉強する",
            iconName: "book.closed.fill",
            cueText: "朝ごはんの後",
            streakText: "6日連続！",
            hasStreak: true,
            progressText: nil,
            progressFraction: 1.0 / 3.0,
            progressCount: 1,
            progressTarget: 3,
            timerStatusText: nil,
            timerTargetDurationMinutes: 10,
            isTimerActive: false,
            isCompleted: false,
            isHighlighted: false,
            allowsEditing: true,
            highlightsDeferredReport: false,
            completionActionTrigger: 0,
            reportsCompletionButtonFrame: false,
            onEdit: {},
            onStartTimer: {},
            onAdvance: { true },
            onUndoCompletion: { true },
            onCompletionButtonFrameChange: { _ in }
        )
        RoutineTaskRow(
            title: "散歩する",
            iconName: "figure.walk",
            cueText: nil,
            streakText: "5日連続！",
            hasStreak: true,
            progressText: nil,
            progressFraction: 1,
            progressCount: 1,
            progressTarget: 1,
            timerStatusText: nil,
            timerTargetDurationMinutes: nil,
            isTimerActive: false,
            isCompleted: true,
            isHighlighted: false,
            allowsEditing: true,
            highlightsDeferredReport: false,
            completionActionTrigger: 0,
            reportsCompletionButtonFrame: false,
            onEdit: {},
            onStartTimer: {},
            onAdvance: { true },
            onUndoCompletion: { true },
            onCompletionButtonFrameChange: { _ in }
        )
    }
    .padding()
    .background(AppColor.background)
}
