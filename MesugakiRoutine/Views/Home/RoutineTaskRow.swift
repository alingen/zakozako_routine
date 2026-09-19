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
    let isEditing: Bool
    let isHighlighted: Bool
    let allowsEditing: Bool
    let onEdit: () -> Void
    let onStartTimer: () -> Void
    let onAdvance: () -> Bool
    let onUndoCompletion: () -> Bool

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isHighlighted ? 8 : 0)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            isHighlighted ? AppColor.primarySoft.opacity(0.46) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColor.primary.opacity(0.55), lineWidth: 1.5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isCompleted)
        .accessibilityElement(children: .contain)
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
                taskSummary(showsEditChevron: isEditing)
            }
            .buttonStyle(RoutineRowPressStyle())
            .accessibilityLabel(taskAccessibilityLabel)
            .accessibilityHint("タップして内容を編集")
        } else {
            taskSummary(showsEditChevron: isEditing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(taskAccessibilityLabel)
                .accessibilityHint("右側の丸をタップして達成を報告")
        }
    }

    private func taskSummary(showsEditChevron: Bool) -> some View {
        HStack(spacing: 12) {
            RoutineProgressPie(
                progress: progressFraction,
                size: 40,
                tint: AppColor.primary,
                centerSystemImage: iconName ?? "checklist"
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let cueText, !cueText.isEmpty {
                    Label(cueText, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(streakText)
                        .foregroundStyle(hasStreak ? AppColor.success : AppColor.muted)

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

            if showsEditChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
                    .frame(width: 24, height: 40)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var taskAccessibilityLabel: String {
        [title, cueText, streakText, progressText]
            .compactMap { $0 }
            .joined(separator: "、")
    }

    @ViewBuilder
    private var trailingControls: some View {
        if !isEditing {
            HStack(spacing: 8) {
                if let timerTargetDurationMinutes, !isCompleted {
                    Button(action: onStartTimer) {
                        Image(systemName: isTimerActive ? "clock.fill" : "clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isTimerActive ? Color.white : AppColor.primary)
                            .frame(width: 40, height: 40)
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
                    onAdvance: onAdvance,
                    onUndoCompletion: onUndoCompletion
                )
            }
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
    let detailText: String?
    /// 現在の期間に残っている回数の割合。1から始まり、失敗を記録するたびに減る。
    let progressFraction: Double
    let isFailed: Bool
    let needsRepair: Bool
    let onEdit: () -> Void
    let onAction: () -> Void

    /// 「やらないこと」は、失敗していない状態を達成済みとして扱う。
    private var isKeepingPromise: Bool {
        !isFailed && !needsRepair
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)

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
                .frame(width: 40, height: 40)
                .background(AppColor.error.opacity(0.12), in: Circle())
        } else {
            RoutineProgressPie(
                progress: progressFraction,
                size: 40,
                tint: AppColor.primary,
                centerSystemImage: iconName ?? "hand.raised"
            )
        }
    }

    private var stateButton: some View {
        Button(action: onAction) {
            ZStack {
                Circle()
                    .fill(isKeepingPromise ? AppColor.primary : AppColor.surface)

                Circle()
                    .stroke(
                        needsRepair ? AppColor.error : AppColor.primary,
                        lineWidth: isFailed || isKeepingPromise ? 0 : 2.5
                    )

                Image(systemName: stateIconName)
                    .font(.system(size: isFailed ? 25 : 16, weight: .bold))
                    .foregroundStyle(isKeepingPromise ? Color.white : (needsRepair ? AppColor.error : AppColor.primary))
            }
            .frame(width: 40, height: 40)
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

    private var actionAccessibilityLabel: String {
        if needsRepair { return "\(title)のスクリーンタイムを再設定" }
        if isFailed { return "\(title)は失敗" }
        return "\(title)の選択肢"
    }
}

/// 完了操作だけを担当する丸ボタン。約0.4秒で押下→塗り→チェックを表現する。
private struct RoutineCompletionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let isCompleted: Bool
    let progressCount: Int
    let progressTarget: Int
    let onAdvance: () -> Bool
    let onUndoCompletion: () -> Bool

    @State private var fillProgress: CGFloat = 0
    @State private var showsCheckmark = false
    @State private var isAnimating = false
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

    var body: some View {
        Button(action: toggleCompletion) {
            ZStack {
                Circle()
                    .fill(AppColor.surface)

                Circle()
                    .fill(AppColor.primary)
                    .scaleEffect(reduceMotion ? 1 : displayedFillProgress)
                    .opacity(displayedFillProgress)

                Circle()
                    .stroke(
                        displayedFillProgress > 0 ? AppColor.primary : AppColor.border,
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
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(RoutineCompletionPressStyle())
        .disabled(isAnimating)
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

                if !completesWithNextTap {
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

struct AddRoutineTaskRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 40, height: 40)
                    .background(AppColor.primarySoft, in: Circle())

                Text("約束を追加")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 40, height: 40)
                    .background(AppColor.primarySoft, in: Circle())

                Text("やらないことを決める")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
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
    /// ホームのフィード型カードで、区切り線をアイコン後ろの本文位置に揃える。
    func homeFeedListRow() -> some View {
        listRowBackground(AppColor.surface)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 52 }
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
            isEditing: false,
            isHighlighted: false,
            allowsEditing: true,
            onEdit: {},
            onStartTimer: {},
            onAdvance: { true },
            onUndoCompletion: { true }
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
            isEditing: false,
            isHighlighted: false,
            allowsEditing: true,
            onEdit: {},
            onStartTimer: {},
            onAdvance: { true },
            onUndoCompletion: { true }
        )
    }
    .padding()
    .background(AppColor.background)
}
