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
    /// 縁にあごをのせて斜め左下を指差す(横長 1774×887)。上の余白が少ないカード(一番上)の P2 で使う。
    static let pointLeft = "mini_point_left"
    static let pointLeftAspectRatio: CGFloat = 887.0 / 1774.0
    static let pointLeftEdgeRatio: CGFloat = 0.834
    /// 縁をつかみ、頬に指を当てて値踏みする顔で覗く(正方形)。ホームを開いたときの「本人への話」で使う。
    static let grabTheEdge = "mini_grab_the_edge"
    /// 画面の上端をつかんで逆さまにぶら下がる(画像の上端が縁、1448×1086)。放置で上から見にくるときに使う。
    static let peekAbove = "mini_peek_above"
    static let peekAboveAspectRatio: CGFloat = 1086.0 / 1448.0
    /// 右の縁から顔を出す(右端の約97%が縁、1086×1448)。放置で右から見にくるときに使う。
    static let peekRight = "mini_peek_right"
    static let peekRightAspectRatio: CGFloat = 1448.0 / 1086.0
    static let peekRightEdgeRatio: CGFloat = 0.967
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
    /// タイマー付きの約束では、完了ボタンの左に時計ボタン(46pt＋間8pt)が並ぶので、そこまで避ける。
    static let protectedTrailingWidthWithTimer: CGFloat = 126
    static let screenMargin: CGFloat = 16
}

private struct RioProtectedTrailingWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = RioPeekLayout.protectedTrailingWidth
}

extension EnvironmentValues {
    /// 莉央と吹き出しを載せない右端の幅。画面にタイマー付きの約束があるときは広げる。
    var rioProtectedTrailingWidth: CGFloat {
        get { self[RioProtectedTrailingWidthKey.self] }
        set { self[RioProtectedTrailingWidthKey.self] = newValue }
    }
}

/// P1「ひょこっ」: 約束を達成したとき、タブバーの上あたりに左から横に滑り込んで耳打ちする。
/// 吹き出しは顔の右に出し、下の約束カードに被せる(右端の列は避ける)。
struct RioPopUpReaction: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rioProtectedTrailingWidth) private var protectedTrailingWidth

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
        max(110, containerWidth - RioPeekLayout.screenMargin - protectedTrailingWidth - bubbleLeading)
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

/// ホームを開いたとき、本人に向けた話(久しぶり・途切れた・守れた)をするときの内容。
struct RioGrabPeekRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// ホームを開いたときの「本人への話」: タブバーの上端を縁に見立てて、mini_grab_the_edge(縁をつかみ、
/// 頬に指を当てて値踏みする顔)がせり上がり、右上に吹き出しを出す。特定のカードの話ではないので指差さない。
/// 左から中央寄りに置き、右端の列(完了ボタン・時計ボタン)にはかからない。
struct RioEdgeGrabPeek: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rioProtectedTrailingWidth) private var protectedTrailingWidth

    let request: RioGrabPeekRequest
    let containerWidth: CGFloat
    /// 縁にする線(層の下端=タブバーの上端)の、層の上端からの位置。
    let bottomEdge: CGFloat
    let dismissTrigger: Int
    let onFinished: () -> Void

    @State private var isRisen = false
    @State private var showsBubble = false
    @State private var isFinishing = false

    private let imageWidth: CGFloat = 120
    private let imageLeading: CGFloat = 32
    /// 素材の縁の線は上から約77%。縁をつかむこぶしまで見せるため約81%で切る。
    private var heightAboveEdge: CGFloat { imageWidth * 0.81 }
    private var imageTop: CGFloat { bottomEdge - heightAboveEdge }
    private var faceCenter: CGPoint {
        CGPoint(x: imageLeading + imageWidth * 0.48, y: imageTop + imageWidth * 0.5)
    }
    private var bubbleLeading: CGFloat { imageLeading + imageWidth * 0.78 }
    private var bubbleMaxWidth: CGFloat {
        max(110, containerWidth - RioPeekLayout.screenMargin - protectedTrailingWidth - bubbleLeading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(RioMiniAsset.grabTheEdge)
                .resizable()
                .frame(width: imageWidth, height: imageWidth)
                .offset(y: isRisen || reduceMotion ? 0 : heightAboveEdge + 4)
                .opacity(reduceMotion && !isRisen ? 0 : 1)
                // 縁(タブバーの上端)より下は描かない。
                .frame(width: imageWidth, height: heightAboveEdge, alignment: .top)
                .clipped()
                .offset(x: imageLeading, y: imageTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Circle()
                .fill(Color.clear)
                .contentShape(Circle())
                .frame(width: 88, height: 88)
                .offset(x: faceCenter.x - 44, y: faceCenter.y - 44)
                .onTapGesture { finish() }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in if value.translation.height > 16 { finish() } }
                )
                .allowsHitTesting(isRisen)
                .accessibilityElement()
                .accessibilityLabel("莉央、\(request.text)")
                .accessibilityHint("ダブルタップで下がる")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { finish() }

            // 吹き出しの左下を、頭の右上に合わせる。点(1pt)の overlay にして、ほかの部品の位置に影響させない。
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
                .offset(x: bubbleLeading, y: imageTop + imageWidth * 0.35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: request.id) { await runLifecycle() }
        .onChange(of: dismissTrigger) { _, _ in finish() }
    }

    private func runLifecycle() async {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.74)) {
            isRisen = true
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.15)) { showsBubble = true }
        do {
            try await Task.sleep(for: .seconds(RioPeekTiming.bubbleSeconds(for: request.text) + 1))
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
            isRisen = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioPeekTiming.sinkSeconds))
            onFinished()
        }
    }
}

/// P2「ちょこん」で出す内容。どの約束カードの上に、どちらの構図で出すか。
struct RioCardPeekRequest: Identifiable, Equatable {
    /// 指差す構図。カードの上の余白で使い分ける。
    enum Style: Equatable {
        /// 縁から身を乗り出して斜め右下を指差す(mini_point)。上に約100ptの余白が要る。
        case leanOver
        /// 縁にあごをのせて斜め左下を指差す横長の構図(mini_point_left)。上は約50ptで足り、一番上のカードにも出せる。
        /// 吹き出しは莉央の左の見出しの行に1行で出すので、短いセリフだけにする。
        case chinOnEdge
    }

    let id = UUID()
    let routineID: UUID
    let text: String
    var style: Style = .leanOver
}

/// P2「ちょこん」: 未達成の約束カードの上端から身を乗り出し、カードを指差して「これ、まだでしょ？」とつつく。
/// まず縁の線より上だけ見せてせり上がり(カードの後ろから出てくる)、そのあと縁の下へ指先を出す。
struct RioCardPeek: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rioProtectedTrailingWidth) private var protectedTrailingWidth

    let request: RioCardPeekRequest
    /// 対象カードの位置(この層の座標)。
    let cardFrame: CGRect
    let dismissTrigger: Int
    let onFinished: () -> Void

    @State private var isRisen = false
    @State private var showsFinger = false
    @State private var showsBubble = false
    @State private var isFinishing = false

    /// 表示する素材の幅。どちらの構図でも顔の幅が約35〜45ptになる。
    static let imageWidth: CGFloat = 124

    /// 縁の線(カードの上端)より上に出る高さ。これより上に余白があるカードだけを対象にする。
    static func heightAboveEdge(_ style: RioCardPeekRequest.Style) -> CGFloat {
        switch style {
        case .leanOver: return imageWidth * RioMiniAsset.pointEdgeRatio
        case .chinOnEdge: return imageWidth * RioMiniAsset.pointLeftAspectRatio * RioMiniAsset.pointLeftEdgeRatio
        }
    }

    private var style: RioCardPeekRequest.Style { request.style }
    private var imageWidth: CGFloat { Self.imageWidth }
    private var imageHeight: CGFloat {
        style == .leanOver ? imageWidth : imageWidth * RioMiniAsset.pointLeftAspectRatio
    }
    private var assetName: String { style == .leanOver ? RioMiniAsset.point : RioMiniAsset.pointLeft }
    private var edgeY: CGFloat { Self.heightAboveEdge(style) }
    /// 素材の左端。
    /// - leanOver: 指先(画像の左から約91%)がカードのタイトルの頭あたりを指すように置く。
    /// - chinOnEdge: 指先(画像の左から約25%)がカードの中ほど(左から約57%)を指すように置く。
    ///   莉央は見出しの「1 / 3」の上に来るが、「＋」と右端の列にはかからない。
    private var imageLeading: CGFloat {
        switch style {
        case .leanOver: return cardFrame.minX - 8
        case .chinOnEdge: return cardFrame.minX + cardFrame.width * 0.57 - imageWidth * 0.25
        }
    }
    private var imageTop: CGFloat { cardFrame.minY - edgeY }
    /// 顔の中心(画像に対する割合)。当たり判定に使う。
    private var faceCenter: CGPoint {
        style == .leanOver
            ? CGPoint(x: imageLeading + imageWidth * 0.47, y: imageTop + imageHeight * 0.42)
            : CGPoint(x: imageLeading + imageWidth * 0.54, y: imageTop + imageHeight * 0.59)
    }

    private var bubbleLeading: CGFloat { imageLeading + imageWidth * 0.72 }
    private var bubbleMaxWidth: CGFloat {
        max(110, cardFrame.maxX - protectedTrailingWidth - bubbleLeading)
    }
    /// chinOnEdge の吹き出しの右端(莉央の髪の左端の少し左)。
    private var leftBubbleTrailing: CGFloat { imageLeading + imageWidth * 0.17 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(assetName)
                .resizable()
                .frame(width: imageWidth, height: imageHeight)
                .offset(y: isRisen || reduceMotion ? 0 : edgeY + 4)
                .opacity(reduceMotion && !isRisen ? 0 : 1)
                // せり上がる間は縁の線で切ってカードの後ろにいるように見せ、出きってから指先を縁の下へ出す。
                .mask(alignment: .top) {
                    Rectangle().frame(height: showsFinger ? imageHeight : edgeY)
                }
                .frame(width: imageWidth, height: imageHeight, alignment: .top)
                .offset(x: imageLeading, y: imageTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Circle()
                .fill(Color.clear)
                .contentShape(Circle())
                .frame(width: style == .leanOver ? 84 : 64, height: style == .leanOver ? 84 : 64)
                .offset(
                    x: faceCenter.x - (style == .leanOver ? 42 : 32),
                    y: faceCenter.y - (style == .leanOver ? 42 : 32)
                )
                .onTapGesture { finish() }
                .allowsHitTesting(isRisen)
                .accessibilityElement()
                .accessibilityLabel("莉央、\(request.text)")
                .accessibilityHint("ダブルタップで下がる")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { finish() }

            // 吹き出しは点(1pt)の overlay にして、吹き出しの高さがほかの部品の位置に影響しないようにする。
            if style == .leanOver {
                // 左下を、髪の右の「縁の線の少し上」に合わせる。
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
            } else {
                // 右端を莉央の左に、縦の中央を見出しの行に合わせて1行で出す(見出しの文字は数秒だけ隠れる)。
                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: .trailing) {
                        if showsBubble {
                            RioPeekBubble(text: request.text)
                                .lineLimit(1)
                                .fixedSize()
                                .onTapGesture { finish() }
                                .accessibilityHidden(true)
                                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                        }
                    }
                    .offset(x: leftBubbleTrailing, y: cardFrame.minY - 24)
            }
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

/// 約束を追加した直後の反応は1日1回まで(午前4時区切り)。
enum RioRoutineAddedSchedule {
    private static let key = "rioRoutineAdded.lastShownDay"

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

/// 放置で見にくる莉央(上から/右から)。未達成が残っていれば上から催促、全部終わっていれば右からからかう。
struct RioIdlePeekRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        /// 上からぶら下がる。未達成の約束名があればセリフに使う。
        case above(unfinishedRoutineTitle: String?)
        /// 右の縁から、達成済みカードの高さで顔を出す。
        case right(routineID: UUID)
    }

    let id = UUID()
    let kind: Kind
    /// タップしたときに言う CMS の条件のセリフ。未指定なら表示先に合う reaction_lines を抽選。
    var preferredText: String? = nil
    let shownAt = Date()
}

/// 放置で来た莉央の共通の流れ。来たときは無言で、タップされたら一言話して帰る。12秒触られなければ黙って帰る。
private struct RioIdlePeekLifecycle {
    static let silentStaySeconds: Double = 12
    static let slideSeconds: Double = 0.25
}

/// 放置で来た莉央が帰るとき、ユーザーがすぐ払ったかどうか(続けてすぐ払われたらその日は来ない)。
enum RioIdlePeekEnding {
    /// タップして話した(かまってもらえた)。
    case talked
    /// 何もされずに時間で帰った。
    case timedOut
    /// スワイプ・スクロールなどで払われた。`quickly` は出てから2秒以内。
    case dismissed(quickly: Bool)
}

/// 放置パターン「上から」: 安全領域の上端(ステータスバーの下)をつかみ、逆さまにぶら下がって覗き込む。
/// 見出しの「＋」と右端の列にはかからないよう、顔の中心を画面幅の約25%に置く。
struct RioIdleAbovePeek: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rioProtectedTrailingWidth) private var protectedTrailingWidth

    let request: RioIdlePeekRequest
    let containerWidth: CGFloat
    let dismissTrigger: Int
    var onTalk: () -> String? = { nil }
    let onFinished: (RioIdlePeekEnding) -> Void

    @State private var isShown = false
    @State private var swing: Double = 0
    @State private var bubbleText: String?
    @State private var isFinishing = false

    private let imageWidth: CGFloat = 124
    private var imageHeight: CGFloat { imageWidth * RioMiniAsset.peekAboveAspectRatio }
    /// 顔の中心(画像の左から約52%・上から約38%)。
    private var faceCenter: CGPoint {
        CGPoint(x: imageLeading + imageWidth * 0.52, y: imageHeight * 0.38)
    }
    private var imageLeading: CGFloat { max(8, containerWidth * 0.25 - imageWidth * 0.52) }
    private var bubbleLeading: CGFloat { imageLeading + imageWidth * 0.86 }
    private var bubbleMaxWidth: CGFloat {
        max(110, containerWidth - RioPeekLayout.screenMargin - protectedTrailingWidth - bubbleLeading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(RioMiniAsset.peekAbove)
                .resizable()
                .frame(width: imageWidth, height: imageHeight)
                // 縁(上端)をつかんだ手を支点に、下りてきて小さく揺れて止まる。
                .rotationEffect(.degrees(swing), anchor: .top)
                .offset(y: isShown || reduceMotion ? 0 : -imageHeight - 4)
                .opacity(reduceMotion && !isShown ? 0 : 1)
                // 縁より上(ステータスバーの側)には描かない。
                .frame(width: imageWidth, height: imageHeight, alignment: .top)
                .clipped()
                .offset(x: imageLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: imageWidth * 0.7, height: imageHeight * 0.8)
                .offset(x: imageLeading + imageWidth * 0.15)
                .onTapGesture { talk() }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.height < -16 { finish(.dismissed(quickly: isQuick)) }
                        }
                )
                .allowsHitTesting(isShown && bubbleText == nil)
                .accessibilityElement()
                .accessibilityLabel("莉央がのぞいている")
                .accessibilityHint("ダブルタップで話しかける")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { talk() }

            Color.clear
                .frame(width: 1, height: 1)
                .overlay(alignment: .leading) {
                    if let bubbleText {
                        RioPeekBubble(text: bubbleText)
                            .frame(width: bubbleMaxWidth, alignment: .leading)
                            .onTapGesture { finish(.talked) }
                            .accessibilityHidden(true)
                            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                    }
                }
                .offset(x: bubbleLeading, y: faceCenter.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: request.id) { await arrive() }
        .onChange(of: dismissTrigger) { _, _ in finish(.dismissed(quickly: isQuick)) }
    }

    private var isQuick: Bool { Date().timeIntervalSince(request.shownAt) < 2 }

    private func arrive() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.15)) { isShown = true }
        } else {
            swing = -7
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { isShown = true }
            withAnimation(.interpolatingSpring(stiffness: 90, damping: 6).delay(0.15)) { swing = 0 }
        }
        do {
            try await Task.sleep(for: .seconds(RioIdlePeekLifecycle.silentStaySeconds))
        } catch { return }
        if bubbleText == nil { finish(.timedOut) }
    }

    private func talk() {
        guard bubbleText == nil, !isFinishing else { return }
        guard let text = request.preferredText ?? onTalk() else { finish(.talked); return }
        withAnimation(.easeOut(duration: 0.15)) { bubbleText = text }
        AccessibilityNotification.Announcement("莉央、\(text)").post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioPeekTiming.bubbleSeconds(for: text)))
            finish(.talked)
        }
    }

    private func finish(_ ending: RioIdlePeekEnding) {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: RioIdlePeekLifecycle.slideSeconds)) {
            bubbleText = nil
            isShown = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioIdlePeekLifecycle.slideSeconds))
            onFinished(ending)
        }
    }
}

/// 放置パターン「右から」: 全部達成したあと、達成済みカードの高さで右の縁から顔を出してからかう。
/// 完了ボタンの列を覆うが、全部終わっていてその列の役目が済んだときだけ出す。
/// 当たり判定は見えている体全体にして、下のチェックを誤って取り消させない(1回目のタップは莉央への反応)。
struct RioIdleRightPeek: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: RioIdlePeekRequest
    /// 顔の高さを合わせる達成済みカードの位置(この層の座標)。
    let cardFrame: CGRect
    let containerWidth: CGFloat
    let dismissTrigger: Int
    var onTalk: () -> String? = { nil }
    let onFinished: (RioIdlePeekEnding) -> Void

    @State private var isShown = false
    @State private var bubbleText: String?
    @State private var isFinishing = false

    private let imageWidth: CGFloat = 104
    private var imageHeight: CGFloat { imageWidth * RioMiniAsset.peekRightAspectRatio }
    /// 素材の縁の線を画面の右端に合わせる。
    private var imageLeading: CGFloat { containerWidth - imageWidth * RioMiniAsset.peekRightEdgeRatio }
    /// 顔(素材の上から約42%)をカードの縦の中央に合わせる。
    private var imageTop: CGFloat { cardFrame.midY - imageHeight * 0.42 }
    private var faceLeft: CGFloat { imageLeading + imageWidth * 0.36 }
    private var bubbleMaxWidth: CGFloat { max(150, faceLeft - 8 - RioPeekLayout.screenMargin) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(RioMiniAsset.peekRight)
                .resizable()
                .frame(width: imageWidth, height: imageHeight)
                .offset(x: isShown || reduceMotion ? 0 : imageWidth)
                .opacity(reduceMotion && !isShown ? 0 : 1)
                .offset(x: imageLeading, y: imageTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: containerWidth - faceLeft, height: imageHeight * 0.9)
                .offset(x: faceLeft, y: imageTop + imageHeight * 0.05)
                .onTapGesture { talk() }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.width > 16 { finish(.dismissed(quickly: isQuick)) }
                        }
                )
                .allowsHitTesting(isShown)
                .accessibilityElement()
                .accessibilityLabel("莉央がのぞいている")
                .accessibilityHint("ダブルタップで話しかける")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { talk() }

            // 吹き出しは顔の左(画面の内側)に出す。右端を顔の左に合わせる。
            Color.clear
                .frame(width: 1, height: 1)
                .overlay(alignment: .trailing) {
                    if let bubbleText {
                        RioPeekBubble(text: bubbleText)
                            .frame(width: bubbleMaxWidth, alignment: .trailing)
                            .onTapGesture { finish(.talked) }
                            .accessibilityHidden(true)
                            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                    }
                }
                .offset(x: faceLeft - 4, y: imageTop + imageHeight * 0.42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: request.id) { await arrive() }
        .onChange(of: dismissTrigger) { _, _ in finish(.dismissed(quickly: isQuick)) }
    }

    private var isQuick: Bool { Date().timeIntervalSince(request.shownAt) < 2 }

    private func arrive() async {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.72)) {
            isShown = true
        }
        do {
            try await Task.sleep(for: .seconds(RioIdlePeekLifecycle.silentStaySeconds))
        } catch { return }
        if bubbleText == nil { finish(.timedOut) }
    }

    private func talk() {
        guard bubbleText == nil, !isFinishing else { return }
        guard let text = request.preferredText ?? onTalk() else { finish(.talked); return }
        withAnimation(.easeOut(duration: 0.15)) { bubbleText = text }
        AccessibilityNotification.Announcement("莉央、\(text)").post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioPeekTiming.bubbleSeconds(for: text)))
            finish(.talked)
        }
    }

    private func finish(_ ending: RioIdlePeekEnding) {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: RioIdlePeekLifecycle.slideSeconds)) {
            bubbleText = nil
            isShown = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(RioIdlePeekLifecycle.slideSeconds))
            onFinished(ending)
        }
    }
}

/// 頼んでいない介入(P2・放置)の回数の決まり: 開くたび1回、1日3回まで、20分空ける、
/// 出てすぐ払われるのが2回続いたらその日はもう来ない。1日は午前4時区切り。
enum RioUnrequestedPeekSchedule {
    private static let dayKey = "rioUnrequestedPeek.day"
    private static let countKey = "rioUnrequestedPeek.count"
    private static let lastShownKey = "rioUnrequestedPeek.lastShownAt"
    private static let quickDismissStreakKey = "rioUnrequestedPeek.quickDismissStreak"

    static let dailyLimit = 3
    static let minimumInterval: TimeInterval = 20 * 60

    static func canShow(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        resetIfNewDay(now: now, defaults: defaults)
        guard defaults.integer(forKey: countKey) < dailyLimit,
              defaults.integer(forKey: quickDismissStreakKey) < 2 else { return false }
        if let last = defaults.object(forKey: lastShownKey) as? Date,
           now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        return true
    }

    static func markShown(now: Date = .now, defaults: UserDefaults = .standard) {
        resetIfNewDay(now: now, defaults: defaults)
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
        defaults.set(now, forKey: lastShownKey)
    }

    static func record(_ ending: RioIdlePeekEnding, now: Date = .now, defaults: UserDefaults = .standard) {
        resetIfNewDay(now: now, defaults: defaults)
        switch ending {
        case .dismissed(quickly: true):
            defaults.set(defaults.integer(forKey: quickDismissStreakKey) + 1, forKey: quickDismissStreakKey)
        case .talked:
            defaults.set(0, forKey: quickDismissStreakKey)
        case .timedOut, .dismissed(quickly: false):
            break
        }
    }

    private static func resetIfNewDay(now: Date, defaults: UserDefaults) {
        let day = AppDay.startOfDay(for: now)
        guard (defaults.object(forKey: dayKey) as? Date) != day else { return }
        defaults.set(day, forKey: dayKey)
        defaults.set(0, forKey: countKey)
        defaults.set(0, forKey: quickDismissStreakKey)
        defaults.removeObject(forKey: lastShownKey)
    }
}
