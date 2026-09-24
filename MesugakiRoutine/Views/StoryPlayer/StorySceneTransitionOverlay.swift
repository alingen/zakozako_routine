import SwiftUI

/// A full-height panel moves through the viewport. Its lower edge extends
/// beyond the screen while moving, so controls cannot peek out below it.
enum StorySlideTransitionGeometry {
    static func panelOriginY(
        height: CGFloat,
        progress: Double,
        phase: StorySceneTransitionState.Phase
    ) -> CGFloat {
        let height = height.isFinite ? max(0, height) : 0
        let fraction = CGFloat(progress.isFinite ? min(1, max(0, progress)) : 0)
        switch phase {
        case .covering: return height * (1 - fraction)
        case .covered: return 0
        case .revealing: return height * fraction
        }
    }

    static func coveredRect(
        size: CGSize,
        progress: Double,
        phase: StorySceneTransitionState.Phase
    ) -> CGRect {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let originY = panelOriginY(height: height, progress: progress, phase: phase)
        return CGRect(x: 0, y: originY, width: width, height: height - originY)
    }

    static func showsIndicator(progress: Double, phase: StorySceneTransitionState.Phase) -> Bool {
        switch phase {
        case .covering: return progress >= 0.51
        case .covered: return true
        case .revealing: return progress <= 0.49
        }
    }
}

/// The solid slide is one SwiftUI layer. Canvas draws only the loading dots;
/// the background, portrait, text and controls themselves never move.
struct StorySceneTransitionOverlay: View {
    let state: StorySceneTransitionState

    var body: some View {
        GeometryReader { proxy in
            let clockOrigin = Date().timeIntervalSinceReferenceDate - ProcessInfo.processInfo.systemUptime

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - clockOrigin - state.startedAt)
                let progress = progress(at: elapsed)

                ZStack(alignment: .topLeading) {
                    if state.reduceMotion || state.configuration.type == .crossFade {
                        AppColor.primary
                            .opacity(state.phase == .covered ? 1 : (state.phase == .covering ? progress : 1 - progress))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        AppColor.primary
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .offset(y: StorySlideTransitionGeometry.panelOriginY(
                                height: proxy.size.height,
                                progress: progress,
                                phase: state.phase
                            ))

                        Canvas { context, size in
                            #if DEBUG
                            StoryTransitionCanvasProbe.shared.record(phase: state.phase)
                            #endif
                            if StorySlideTransitionGeometry.showsIndicator(progress: progress, phase: state.phase) {
                                drawIndicator(context: &context, size: size, elapsed: elapsed)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { }
        .accessibilityHidden(true)
    }

    private func progress(at elapsed: TimeInterval) -> Double {
        let duration: Double
        switch state.phase {
        case .covering:
            duration = state.configuration.effectiveCoverDuration(reduceMotion: state.reduceMotion)
        case .covered:
            return 1
        case .revealing:
            duration = state.configuration.effectiveRevealDuration(reduceMotion: state.reduceMotion)
        }
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    private func drawIndicator(context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let radius: CGFloat = 4
        let spacing: CGFloat = 18
        for index in 0..<3 {
            let wave = (sin((elapsed - Double(index) * 0.11) * 2 * .pi / 0.55) + 1) / 2
            let rect = CGRect(
                x: size.width / 2 + CGFloat(index - 1) * spacing - radius,
                y: size.height / 2 - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(AppColor.background.opacity(0.45 + 0.55 * wave))
            )
        }
    }
}
