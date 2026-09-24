#if DEBUG
import SwiftUI
import UIKit

/// Counts actual Canvas callback updates, separately from display-link ticks.
/// Covered/static frames intentionally do not contribute to this average.
final class StoryTransitionCanvasProbe: @unchecked Sendable {
    static let shared = StoryTransitionCanvasProbe()
    private let lock = NSLock()
    private var enabled = false
    private var previous: (StorySceneTransitionState.Phase, TimeInterval)?
    private var intervals: [Double] = []

    func start() {
        lock.lock()
        defer { lock.unlock() }
        enabled = true
        previous = nil
        intervals = []
    }

    func record(phase: StorySceneTransitionState.Phase) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if phase != .covered, let previous, previous.0 == phase {
            let delta = time - previous.1
            if delta > 0.001 { intervals.append(delta) }
        }
        previous = (phase, time)
    }

    func finish() -> (fps: Double, samples: Int) {
        lock.lock()
        defer { lock.unlock() }
        enabled = false
        let total = intervals.reduce(0, +)
        return (total > 0 ? Double(intervals.count) / total : 0, intervals.count)
    }
}

/// Launch with --color-slide-sample. Uses the production playback container,
/// renderer and engine, but the app creates an in-memory store for this launch.
struct StorySceneTransitionSample: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "color_slide_sample", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let scenario = try? JSONDecoder().decode(StoryScenario.self, from: data) {
            StoryPlaybackContainerView(
                launch: StoryLaunchRequest(
                    title: "カラースライド確認", playbackKey: "debug:colorSlide",
                    scenario: scenario, event: nil
                ),
                allowsSkip: false,
                onClose: {}
            )
        } else {
            Text("確認用シナリオを読み込めませんでした")
        }
    }
}

/// Debug-only display-link cadence measurements; not a physical-device GPU
/// benchmark. Also records the wall-clock duration of the complete transition.
@MainActor
final class StoryTransitionFrameDiagnostics: NSObject {
    private var link: CADisplayLink?
    private var start: TimeInterval = 0
    private var previous: TimeInterval?
    private var intervals: [Double] = []

    func update(isActive: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("--color-slide-sample") else { return }
        if isActive, link == nil {
            start = ProcessInfo.processInfo.systemUptime
            previous = nil
            intervals = []
            StoryTransitionCanvasProbe.shared.start()
            let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            self.link = link
            link.add(to: .main, forMode: .common)
        } else if !isActive, link != nil {
            link?.invalidate()
            link = nil
            let duration = ProcessInfo.processInfo.systemUptime - start
            let average = intervals.reduce(0, +) / Double(max(1, intervals.count))
            let sorted = intervals.sorted()
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            let canvas = StoryTransitionCanvasProbe.shared.finish()
            NSLog("ColorSlide duration=%.3fs displayLink=%.1ffps p95=%.1fms samples=%d canvas=%.1ffps draws=%d", duration, average > 0 ? 1 / average : 0, p95 * 1_000, intervals.count, canvas.fps, canvas.samples)
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        if let previous { intervals.append(link.timestamp - previous) }
        previous = link.timestamp
    }
}
#endif
