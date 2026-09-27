import SwiftUI
import UIKit

// ホームの一覧の上に重ねる、莉央専用の層の部品。
// 莉央は「道具の外の枠」ではなく、約束カードの上に顔を出してちょっかいを出す。
// ただし操作は邪魔しない: 完了ボタンのある右端の列は覆わず、スクロールや吹き出し・莉央のタップですぐ引っ込む。

/// ミニキャラの素材。表情差分が届いたら、場面ごとの名前をここで分ける。
enum RioMiniAsset {
    /// 左から身を乗り出して耳打ちする(左端で切れている構図、1060×1484)。P1 で使う。
    static let whisper = "mini_whisper"
    static let whisperAspectRatio: CGFloat = 1484.0 / 1060.0
    /// 縁から身を乗り出して斜め右下を指差す(正方形)。P2 で使う。
    static let point = "mini_point"
    /// 画像の上端から「縁の線」(カードの上端に合わせる線)までの割合。
    static let pointEdgeRatio: CGFloat = 0.805
    /// 縁をつかんで覗く(正方形)。P3・P4 用。
    static let grabTheEdge = "mini_grab_the_edge"
}

/// 層の上に出す莉央の吹き出し。ホームや煽りと同じピンクで、下のカードに被っても読めるよう薄い影を付ける。
struct RioPeekBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColor.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColor.primarySoft)
                    .shadow(color: AppColor.text.opacity(0.14), radius: 10, y: 3)
            }
    }
}

/// 出てから引っ込むまでの時間。VoiceOver では読み終えられるよう長めにする。
enum RioPeekTiming {
    static func bubbleSeconds(for text: String) -> Double {
        if UIAccessibility.isVoiceOverRunning { return 10 }
        return min(max(Double(text.count) * 0.12 + 1.5, 3), 6)
    }

    /// 吹き出しが消えてから、顔だけ残って沈むまで。
    static let lingerSeconds: Double = 2
    static let sinkSeconds: Double = 0.25
}

/// 右端の列(完了ボタンの丸・「…」)の幅。莉央も吹き出しもここには乗せない。
enum RioPeekLayout {
    static let protectedTrailingWidth: CGFloat = 72
    static let screenMargin: CGFloat = 16
}

/// P1「ひょこっ」: 約束を達成したとき、タブバーの上あたりに左から横に滑り込んで耳打ちする。
/// 吹き出しは顔の右に出し、下の約束カードに被せる(右端の列は避ける)。
struct RioPopUpReaction: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let reaction: RioReaction
    /// 層の幅(画面幅)。吹き出しの幅の上限を決める。
    let containerWidth: CGFloat
    /// 値が変わったら、途中でも引っ込む(スクロール・タップなど)。
    let dismissTrigger: Int
    let onFinished: () -> Void

    @State private var isShown = false
    @State private var showsBubble = false
    @State private var isFinishing = false

    // 幅140pt(高さ約196pt)で描き、下の約2割(足元)はタブバーの後ろに隠す。
    private let imageWidth: CGFloat = 140
    private var imageHeight: CGFloat { imageWidth * RioMiniAsset.whisperAspectRatio }
    private var visibleHeight: CGFloat { imageHeight * 0.8 }
    /// 顔の中心(画像の左から約40%、上から約30%)。
    private var faceCenter: CGPoint { CGPoint(x: imageWidth * 0.4, y: imageHeight * 0.3) }

    private var bubbleLeading: CGFloat { imageWidth * 0.72 }
    private var bubbleMaxWidth: CGFloat {
        max(150, containerWidth - RioPeekLayout.screenMargin - RioPeekLayout.protectedTrailingWidth - bubbleLeading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(RioMiniAsset.whisper)
                .resizable()
                .frame(width: imageWidth, height: imageHeight)
                // 左の画面の外から滑り込む。視差効果を減らす設定ではその場でフェードする。
                .offset(x: isShown || reduceMotion ? 0 : -imageWidth - 8)
                .opacity(reduceMotion && !isShown ? 0 : 1)
                // 足元(下の約2割)はタブバーの後ろに隠す。
                .frame(width: imageWidth, height: visibleHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // 当たり判定は頭と胴のまわりだけ。透明な髪の部分でカードへのタップを奪わない。
            Ellipse()
                .fill(Color.clear)
                .contentShape(Ellipse())
                .frame(width: 110, height: 150)
                .offset(x: faceCenter.x - 55, y: faceCenter.y - 55)
                .onTapGesture { finish() }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.width < -16 || value.translation.height > 16 { finish() }
                        }
                )
                .allowsHitTesting(isShown)
                .accessibilityElement()
                .accessibilityLabel("莉央、\(reaction.text)")
                .accessibilityHint("ダブルタップで下がる")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { finish() }

            // 吹き出しの左端・縦の中央を、顔の右の点に合わせる。点の overlay にして、ほかの部品の位置に影響させない。
            Color.clear
                .frame(width: 1, height: 1)
                .overlay(alignment: .leading) {
                    if showsBubble {
                        RioPeekBubble(text: reaction.text)
                            .frame(width: bubbleMaxWidth, alignment: .leading)
                            .onTapGesture { finish() }
                            .accessibilityHidden(true)
                            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                    }
                }
                .offset(x: bubbleLeading, y: faceCenter.y - 6)
        }
        .frame(width: imageWidth, height: visibleHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .task(id: reaction.id) { await runLifecycle() }
        .onChange(of: dismissTrigger) { _, _ in finish() }
    }

    private func runLifecycle() async {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.74)) {
            isShown = true
        }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.15)) { showsBubble = true }
        do {
            try await Task.sleep(for: .seconds(RioPeekTiming.bubbleSeconds(for: reaction.text)))
        } catch { return }
        withAnimation(.easeOut(duration: 0.2)) { showsBubble = false }
        do {
            try await Task.sleep(for: .seconds(RioPeekTiming.lingerSeconds))
        } catch { return }
        finish()
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: RioPeekTiming.sinkSeconds)) {
            showsBubble = false
            isShown = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioPeekTiming.sinkSeconds))
            onFinished()
        }
    }
}

/// P2「ちょこん」で出す内容。どの約束カードの上に出すか。
struct RioCardPeekRequest: Identifiable, Equatable {
    let id = UUID()
    let routineID: UUID
    let text: String
}

/// P2「ちょこん」: 未達成の約束カードの上端から身を乗り出し、カードを指差して「これ、まだでしょ？」とつつく。
/// まず縁の線より上だけ見せてせり上がり(カードの後ろから出てくる)、そのあと縁の下へ指先を出す。
struct RioCardPeek: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: RioCardPeekRequest
    /// 対象カードの位置(この層の座標)。
    let cardFrame: CGRect
    let dismissTrigger: Int
    let onFinished: () -> Void

    @State private var isRisen = false
    @State private var showsFinger = false
    @State private var showsBubble = false
    @State private var isFinishing = false

    /// 表示する素材の幅(正方形)。顔の幅が約45ptになる。
    static let imageWidth: CGFloat = 124
    /// 縁の線(カードの上端)より上に出る高さ。これより上に余白があるカードだけを対象にする。
    static var heightAboveEdge: CGFloat { imageWidth * RioMiniAsset.pointEdgeRatio }

    private var imageWidth: CGFloat { Self.imageWidth }
    private var edgeY: CGFloat { Self.heightAboveEdge }
    /// 素材の左端。指先(画像の左から約91%)がカードのタイトルの頭あたりを指すように置く。
    private var imageLeading: CGFloat { cardFrame.minX - 8 }
    private var imageTop: CGFloat { cardFrame.minY - edgeY }

    private var bubbleLeading: CGFloat { imageLeading + imageWidth * 0.72 }
    private var bubbleMaxWidth: CGFloat {
        max(140, cardFrame.maxX - RioPeekLayout.protectedTrailingWidth - bubbleLeading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(RioMiniAsset.point)
                .resizable()
                .frame(width: imageWidth, height: imageWidth)
                .offset(y: isRisen || reduceMotion ? 0 : edgeY + 4)
                .opacity(reduceMotion && !isRisen ? 0 : 1)
                // せり上がる間は縁の線で切ってカードの後ろにいるように見せ、出きってから指先を縁の下へ出す。
                .mask(alignment: .top) {
                    Rectangle().frame(height: showsFinger ? imageWidth : edgeY)
                }
                .frame(width: imageWidth, height: imageWidth, alignment: .top)
                .offset(x: imageLeading, y: imageTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Circle()
                .fill(Color.clear)
                .contentShape(Circle())
                .frame(width: 84, height: 84)
                .offset(x: imageLeading + imageWidth * 0.47 - 42, y: imageTop + imageWidth * 0.42 - 42)
                .onTapGesture { finish() }
                .allowsHitTesting(isRisen)
                .accessibilityElement()
                .accessibilityLabel("莉央、\(request.text)")
                .accessibilityHint("ダブルタップで下がる")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { finish() }

            // 吹き出しの左下を、髪の右の「縁の線の少し上」に合わせる。
            // 点(1pt)の overlay にして、吹き出しの高さがほかの部品の位置に影響しないようにする。
            Color.clear
                .frame(width: 1, height: 1)
                .overlay(alignment: .bottomLeading) {
                    if showsBubble {
                        RioPeekBubble(text: request.text)
                            .frame(width: bubbleMaxWidth, alignment: .bottomLeading)
                            .onTapGesture { finish() }
                            .accessibilityHidden(true)
                            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomLeading)))
                    }
                }
                .offset(x: bubbleLeading, y: cardFrame.minY - 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: request.id) { await runLifecycle() }
        .onChange(of: dismissTrigger) { _, _ in finish() }
    }

    private func runLifecycle() async {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.72)) {
            isRisen = true
        }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showsFinger = true }
        withAnimation(.easeOut(duration: 0.15)) { showsBubble = true }
        do {
            try await Task.sleep(for: .seconds(RioPeekTiming.bubbleSeconds(for: request.text)))
        } catch { return }
        withAnimation(.easeOut(duration: 0.2)) { showsBubble = false }
        do {
            try await Task.sleep(for: .seconds(RioPeekTiming.lingerSeconds + 2))
        } catch { return }
        finish()
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: 0.12)) { showsFinger = false }
        withAnimation(.easeIn(duration: RioPeekTiming.sinkSeconds)) {
            showsBubble = false
            isRisen = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioPeekTiming.sinkSeconds))
            onFinished()
        }
    }
}

/// P2 を出すのは1日1回まで(午前4時区切り)。
enum RioCardPeekSchedule {
    private static let key = "rioCardPeek.lastShownDay"

    static func hasShown(on day: Date, defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: key) as? Date) == day
    }

    static func markShown(on day: Date, defaults: UserDefaults = .standard) {
        defaults.set(day, forKey: key)
    }
}

/// ホームの約束カードの位置(グローバル座標)。P2 で顔を出すカードを決めるのに使う。
struct HomeRoutineRowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
