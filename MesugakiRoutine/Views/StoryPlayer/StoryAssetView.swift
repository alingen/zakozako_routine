import SwiftUI
import UIKit

enum StoryAssetPurpose {
    case background
    case image
    case cg

    fileprivate var placeholderSymbol: String {
        switch self {
        case .background:
            return "photo.on.rectangle.angled"
        case .image:
            return "photo"
        case .cg:
            return "photo.artframe"
        }
    }

    fileprivate var accessibilityName: String {
        switch self {
        case .background:
            return "背景"
        case .image:
            return "画像"
        case .cg:
            return "イベント画像"
        }
    }
}

/// CMSのasset IDを安全に描画し、未収録の場合も識別可能な表示を保つ。
struct StoryAssetView: View {
    let assetID: String?
    let purpose: StoryAssetPurpose
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if let assetID = normalizedAssetID, UIImage(named: assetID) != nil {
                Image(assetID)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel("\(purpose.accessibilityName) \(assetID)")
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var normalizedAssetID: String? {
        guard let value = assetID?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [AppColor.primarySoft, AppColor.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: purpose.placeholderSymbol)
                    .font(.title2)
                Text(normalizedAssetID ?? "asset未指定")
                    .font(.caption2.monospaced())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding()
            .foregroundStyle(AppColor.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fallbackAccessibilityLabel)
    }

    private var fallbackAccessibilityLabel: String {
        if let normalizedAssetID {
            return "\(purpose.accessibilityName) \(normalizedAssetID) は未収録です"
        }
        return "\(purpose.accessibilityName)は未指定です"
    }
}
