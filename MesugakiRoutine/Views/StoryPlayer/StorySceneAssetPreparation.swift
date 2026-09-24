import UIKit

/// Shares the decoded images with StoryAssetView, not just UIImage's compressed
/// asset lookup cache. A small cost-bounded cache avoids decoding at the swap.
@MainActor
final class StorySceneAssetPreparation {
    static let shared = StorySceneAssetPreparation()
    private let images = NSCache<NSString, UIImage>()

    private init() {
        images.totalCostLimit = 96 * 1_024 * 1_024
        images.countLimit = 8
    }

    func image(named id: String) -> UIImage? {
        images.object(forKey: id as NSString) ?? UIImage(named: id)
    }

    func prepare(_ ids: [String]) async {
        for id in ids {
            guard !Task.isCancelled else { return }
            guard images.object(forKey: id as NSString) == nil,
                  let image = UIImage(named: id) else { continue }
            let decoded: UIImage = await withCheckedContinuation { continuation in
                image.prepareForDisplay { prepared in
                    continuation.resume(returning: prepared ?? image)
                }
            }
            guard !Task.isCancelled else { return }
            let cost = (decoded.cgImage?.bytesPerRow ?? 0) * (decoded.cgImage?.height ?? 0)
            images.setObject(decoded, forKey: id as NSString, cost: cost)
        }
    }
}

/// A timer ending is not proof that SwiftUI has rendered the opaque cover.
/// The first tick schedules that frame; the second passes its presentation.
@MainActor
private final class StoryRenderedFrameBarrier: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    private var ticks = 0

    static func wait() async {
        let barrier = StoryRenderedFrameBarrier()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(); return }
                barrier.continuation = continuation
                let link = CADisplayLink(target: barrier, selector: #selector(frame))
                barrier.link = link
                link.add(to: .main, forMode: .common)
            }
        } onCancel: {
            Task { @MainActor in barrier.finish() }
        }
    }

    @objc private func frame() {
        ticks += 1
        if ticks >= 2 { finish() }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
func awaitStoryRenderedFrame() async {
    await StoryRenderedFrameBarrier.wait()
}
