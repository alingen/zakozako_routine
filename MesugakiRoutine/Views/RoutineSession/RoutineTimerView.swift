import Combine
import Foundation
import Observation
import SwiftUI

/// 端末時刻を基準にカウントダウンするため、描画更新が止まっても時間がずれない。
@Observable
@MainActor
final class RoutineTimerSession {
    enum Phase: Equatable {
        case running
        case paused
        case completed
        case stopped
    }

    let totalDuration: TimeInterval
    private(set) var remainingDuration: TimeInterval
    private(set) var phase: Phase = .running
    private(set) var completedAt: Date?

    private var deadline: Date?
    private var hasReportedCompletion = false

    init(targetMinutes: Int, now: Date = .now) {
        let safeMinutes = max(targetMinutes, 1)
        totalDuration = TimeInterval(safeMinutes * 60)
        remainingDuration = totalDuration
        deadline = now.addingTimeInterval(totalDuration)
    }

    var displayedRemainingSeconds: Int {
        max(Int(ceil(remainingDuration)), 0)
    }

    var formattedRemainingDuration: String {
        Self.formattedDuration(seconds: displayedRemainingSeconds)
    }

    var remainingFraction: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(remainingDuration / totalDuration, 0), 1)
    }

    /// 目標到達へ遷移した最初の呼び出しだけ、正確な到達時刻を返す。
    @discardableResult
    func refresh(now: Date = .now) -> Date? {
        guard phase == .running, let deadline else { return nil }
        remainingDuration = max(deadline.timeIntervalSince(now), 0)
        guard remainingDuration <= 0 else { return nil }

        phase = .completed
        completedAt = deadline
        self.deadline = nil

        guard !hasReportedCompletion else { return nil }
        hasReportedCompletion = true
        return deadline
    }

    /// 一時停止の直前に時刻を再計算し、ちょうど0秒なら完了として返す。
    @discardableResult
    func pause(now: Date = .now) -> Date? {
        if let completedAt = refresh(now: now) {
            return completedAt
        }
        guard phase == .running else { return nil }
        phase = .paused
        deadline = nil
        return nil
    }

    func resume(now: Date = .now) {
        guard phase == .paused, remainingDuration > 0 else { return }
        deadline = now.addingTimeInterval(remainingDuration)
        phase = .running
    }

    func stop() {
        guard phase != .completed else { return }
        phase = .stopped
        deadline = nil
    }

    static func formattedDuration(seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// タイマー対象の約束を、開始直後からカウントダウンする専用画面。
struct RoutineTimerView: View {
    private let routineTitle: String
    private let routineIconName: String?
    private let targetMinutes: Int
    private let session: RoutineTimerSession
    private let onClose: () -> Void
    private let onStop: () -> Void
    private let onComplete: (Date) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingStop = false
    @State private var hasScheduledCompletion = false
    @State private var completionFeedbackTrigger = 0
    @State private var completionTask: Task<Void, Never>?

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(
        routineTitle: String,
        routineIconName: String?,
        targetMinutes: Int,
        session: RoutineTimerSession,
        onClose: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onComplete: @escaping (Date) -> Void
    ) {
        self.routineTitle = routineTitle
        self.routineIconName = routineIconName
        self.targetMinutes = max(targetMinutes, 1)
        self.session = session
        self.onClose = onClose
        self.onStop = onStop
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { proxy in
            let dialSize = min(proxy.size.width - 48, min(proxy.size.height * 0.46, 360))

            ScrollView {
                VStack(spacing: 28) {
                    header

                    VStack(spacing: 10) {
                        if let routineIconName {
                            Image(systemName: routineIconName)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(AppColor.primary)
                                .frame(width: 52, height: 52)
                                .background(AppColor.primarySoft, in: Circle())
                        }

                        Text(routineTitle)
                            .font(.title.bold())
                            .foregroundStyle(AppColor.text)
                            .multilineTextAlignment(.center)

                        Text("目標 \(targetMinutes)分")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                    }
                    .padding(.horizontal, 24)

                    RoutineTimerDial(
                        remainingFraction: session.remainingFraction,
                        timeText: session.formattedRemainingDuration,
                        phase: session.phase,
                        size: dialSize
                    )

                    timerControlButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppColor.background.ignoresSafeArea())
        .interactiveDismissDisabled(hasScheduledCompletion)
        .confirmationDialog(
            "タイマーを終了しますか？",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button("終了する", role: .destructive) {
                let now = Date.now
                if let completedAt = session.refresh(now: now) ?? session.completedAt {
                    finish(at: completedAt)
                } else {
                    session.stop()
                    onStop()
                }
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("ここまでの時間は達成として記録されません。")
        }
        .onReceive(ticker) { date in
            guard scenePhase == .active else { return }
            refresh(at: date)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refresh(at: .now)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            refresh(at: .now)
        }
        .onDisappear {
            completionTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sensoryFeedback(.success, trigger: completionFeedbackTrigger)
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.text)
                    .frame(width: 44, height: 44)
                    .background(AppColor.surface, in: Circle())
                    .overlay(Circle().stroke(AppColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(session.phase == .completed)
            .accessibilityLabel("タイマー画面を閉じる")
            .accessibilityHint("タイマーはそのまま継続します")

            Spacer()

            Button {
                isConfirmingStop = true
            } label: {
                Label("停止", systemImage: "stop.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.error)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(AppColor.surface, in: Capsule())
                    .overlay(Capsule().stroke(AppColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(session.phase == .completed)
        }
    }

    private var timerControlButton: some View {
        Button {
            switch session.phase {
            case .running:
                if let completedAt = session.pause(now: .now) {
                    finish(at: completedAt)
                }
            case .paused:
                session.resume(now: .now)
            case .completed, .stopped:
                break
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: controlSystemImage)
                Text(controlTitle)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColor.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(session.phase == .completed || session.phase == .stopped)
        .opacity(session.phase == .completed ? 0.55 : 1)
        .accessibilityHint(controlAccessibilityHint)
    }

    private var controlSystemImage: String {
        switch session.phase {
        case .running: "pause.fill"
        case .paused: "clock.arrow.circlepath"
        case .completed: "checkmark"
        case .stopped: "stop.fill"
        }
    }

    private var controlTitle: String {
        switch session.phase {
        case .running: "一時停止"
        case .paused: "再開"
        case .completed: "達成！"
        case .stopped: "終了"
        }
    }

    private var controlAccessibilityHint: String {
        switch session.phase {
        case .running: "カウントダウンを一時停止します"
        case .paused: "カウントダウンを再開します"
        case .completed, .stopped: ""
        }
    }

    private func refresh(at date: Date) {
        if let completedAt = session.refresh(now: date) {
            finish(at: completedAt)
        }
    }

    private func finish(at date: Date) {
        guard !hasScheduledCompletion else { return }
        hasScheduledCompletion = true
        isConfirmingStop = false
        completionFeedbackTrigger += 1

        completionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onComplete(date)
        }
    }
}

private struct RoutineTimerDial: View {
    let remainingFraction: Double
    let timeText: String
    let phase: RoutineTimerSession.Phase
    let size: CGFloat

    private var clampedFraction: Double {
        min(max(remainingFraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColor.surface)
                .shadow(color: AppColor.text.opacity(0.08), radius: 20, y: 10)

            Circle()
                .stroke(AppColor.primarySoft, lineWidth: 18)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    AngularGradient(
                        colors: [AppColor.primary, AppColor.secondary, AppColor.primary],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: clampedFraction)

            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(index % 3 == 0 ? AppColor.primary.opacity(0.7) : AppColor.border)
                    .frame(width: 4, height: index % 3 == 0 ? 13 : 8)
                    .offset(y: -(size / 2 - 36))
                    .rotationEffect(.degrees(Double(index) * 30))
            }

            VStack(spacing: 10) {
                Image(systemName: phaseSystemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(phase == .completed ? AppColor.success : AppColor.primary)

                Text(timeText)
                    .font(.system(size: min(44, size * 0.14), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.text)
                    .minimumScaleFactor(0.7)

                Text(phaseTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("残り時間 \(timeText)、\(phaseTitle)")
    }

    private var phaseSystemImage: String {
        switch phase {
        case .running: "clock.fill"
        case .paused: "pause.fill"
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.fill"
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .running: "カウントダウン中"
        case .paused: "一時停止中"
        case .completed: "目標達成"
        case .stopped: "終了"
        }
    }
}

#Preview {
    RoutineTimerView(
        routineTitle: "本を読む",
        routineIconName: "book",
        targetMinutes: 10,
        session: RoutineTimerSession(targetMinutes: 10),
        onClose: {},
        onStop: {},
        onComplete: { _ in }
    )
}
