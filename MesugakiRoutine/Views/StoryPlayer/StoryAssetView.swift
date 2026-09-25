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

/// CMSのasset IDを安全に描画する。未収録の場合は用途別のプレースホルダーを出す。
struct StoryAssetView: View {
    let assetID: String?
    let purpose: StoryAssetPurpose
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if let assetID = normalizedAssetID,
               let image = StorySceneAssetPreparation.shared.image(named: assetID) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(purpose.accessibilityName)
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

            // asset ID は内部値なので画面にも読み上げにも出さない。
            Image(systemName: purpose.placeholderSymbol)
                .font(.title2)
                .foregroundStyle(AppColor.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(purpose.accessibilityName)
    }
}
