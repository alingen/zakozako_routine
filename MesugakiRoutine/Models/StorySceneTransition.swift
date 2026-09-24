import Foundation

/// Opt-in scene_change.command_args.transition. Legacy fade/cut commands keep
/// their existing presentation; an unknown transition never blocks a story.
struct StorySceneTransitionConfiguration: Equatable {
    enum Kind: String { case colorSlide, crossFade }

    let type: Kind
    let duration: Double
    let minimumHold: Double
    let coverDuration: Double
    let revealDuration: Double

    init?(arguments: JSONValue?) {
        guard let value = arguments?["transition"] else {
            return nil
        }
        let typeName = value["type"]?.stringValue ?? value.stringValue ?? ""
        // An unshipped sample used the earlier name. Keep its scenario rows
        // readable while the visible effect takes the new, simpler name.
        guard let kind = Kind(rawValue: typeName == "pixelSpiral" ? "colorSlide" : typeName) else {
            return nil
        }
        func number(_ key: String, default fallback: Double, range: ClosedRange<Double>) -> Double {
            let parsed: Double?
            switch value[key] {
            case .number(let raw): parsed = raw
            case .string(let raw): parsed = Double(raw)
            default: parsed = nil
            }
            let raw = parsed.flatMap { $0.isFinite ? $0 : nil } ?? fallback
            return min(range.upperBound, max(range.lowerBound, raw))
        }
        type = kind
        duration = number("duration", default: 0.70, range: 0.15...5)
        minimumHold = number("minimumHold", default: 0.08, range: 0...max(0, duration - 0.1))
        let movingTime = duration - minimumHold
        // Explicit phase durations act as weights so the total always remains
        // `duration`, including the minimum covered hold.
        let coverWeight = number("coverDuration", default: 0.28, range: 0.01...5)
        let revealWeight = number("revealDuration", default: 0.34, range: 0.01...5)
        coverDuration = movingTime * coverWeight / (coverWeight + revealWeight)
        revealDuration = movingTime - coverDuration
    }

    func effectiveCoverDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.10 : coverDuration
    }

    func effectiveRevealDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.12 : revealDuration
    }
}

struct StorySceneTransitionState: Equatable {
    enum Phase { case covering, covered, revealing }
    let configuration: StorySceneTransitionConfiguration
    let phase: Phase
    let startedAt: TimeInterval
    let reduceMotion: Bool
    var isWaitingForAssets = false
}
