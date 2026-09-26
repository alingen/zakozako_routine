import SwiftUI

struct ZakoNewsFeedSheet: View {
    var mine = false
    @Environment(\.dismiss) private var dismiss
    @State private var store = ZakoNewsStore.shared
    @State private var posts: [ZakoNewsPost] = []
    @State private var selected: ZakoNewsPost?
    @State private var cursor: ZakoNewsPost?
    @State private var hasMore = true
    @State private var loading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // ホームと同じく白いカードで1件ずつ並べ、最後の1件が見えたら続きを自動で読み込む。
            ScrollView {
                LazyVStack(spacing: 8) {
                    if posts.isEmpty && !loading && errorMessage == nil {
                        Text("まだ速報はありません")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    ForEach(posts) { post in
                        Button { selected = post } label: {
                            ZakoNewsRow(post: post, showsMineBadge: !mine)
                                .padding(.horizontal, 14)
                                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            guard post.id == posts.last?.id, hasMore, errorMessage == nil else { return }
                            Task { await load(reset: false) }
                        }
                    }
                    // 引っ張って更新しているときは上のぐるぐるだけにする(下にも出すと中身が動いて更新が取り消される)。
                    if loading && !isRefreshing { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                    if let errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage).font(.footnote).foregroundStyle(AppColor.error)
                            Button("もう一度読み込む") { Task { await load(reset: posts.isEmpty) } }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColor.text)
                                .frame(minHeight: 44)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(AppColor.background)
            .navigationTitle(mine ? "自分の速報" : "みんなのざこ速報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .refreshable {
                // 画面の更新で refreshable の処理が取り消されても通信を最後まで終えられるよう、別の Task で読み込む。
                isRefreshing = true
                await Task { await load(reset: true) }.value
                isRefreshing = false
            }
            .task { await load(reset: true) }
            .sheet(item: $selected, onDismiss: { Task { await load(reset: true) } }) { post in ZakoNewsDetailView(post: post) }
        }.presentationDragIndicator(.visible)
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true
        defer { loading = false }
        do {
            let page = try await store.repository.feed(before: reset ? nil : cursor, ids: nil, mine: mine)
            // 最初から読み直すときも、取得できてから入れ替える(先に空にすると画面が消えて更新が取り消される)。
            if reset {
                posts = page
            } else {
                let known = Set(posts.map(\.id))
                posts.append(contentsOf: page.filter { !known.contains($0.id) })
            }
            cursor = page.last; hasMore = page.count == ZakoNewsConfiguration.batchSize; errorMessage = nil
        } catch {
            // 取り消されただけなら失敗扱いにしない。
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled { return }
            errorMessage = "速報を読み込めませんでした。もう一度お試しください。"
        }
    }
}

struct ZakoNewsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ZakoNewsStore.shared
    @State var post: ZakoNewsPost
    @State private var comment = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var reportMessage: String?
    @State private var showBlock = false
    @State private var showDelete = false
    @State private var showReport = false
    @State private var detent: PresentationDetent = .medium
    /// 開いた時点で自分の投稿のひとことが空なら、入力欄を応援より上に置く(保存後も並びは変えない)。
    @State private var commentFirst = false
    @FocusState private var isCommentFocused: Bool

    var body: some View {
        NavigationStack {
            // 設定画面のような Form ではなく、一覧と同じ組み方の投稿カード → 応援 → (自分の投稿なら)ひとこと、の順に置く。
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    postCard
                    if post.isMine && commentFirst { commentCard }
                    reactionButtons
                    if post.isMine && !commentFirst { commentCard }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(AppColor.error)
                    }
                    if let reportMessage {
                        Text(reportMessage).font(.footnote).foregroundStyle(AppColor.text)
                    }
                }
                .padding()
            }
            .background(AppColor.background)
            .overlay { if working { ProgressView() } }
            .disabled(working).navigationTitle("ざこ速報").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.disabled(working) } }
            .onAppear {
                comment = post.comment
                commentFirst = post.isMine && post.comment.isEmpty
            }
            .task {
                // ひとことを書きに来た人のために、シートが開ききってから入力欄に合わせる。
                guard commentFirst else { return }
                try? await Task.sleep(for: .milliseconds(450))
                isCommentFocused = true
            }
            // キーボードで隠れないよう、入力中はシートを全画面に広げる。
            .onChange(of: isCommentFocused) { _, focused in
                if focused { withAnimation { detent = .large } }
            }
            .task { run { try await reload() } }
            .confirmationDialog("通報理由を選んでください", isPresented: $showReport, titleVisibility: .visible) {
                ForEach(ZakoNewsReportReason.allCases) { reason in
                    Button(reason.title) {
                        run {
                            try await store.repository.report(postID: post.id, reason: reason.rawValue)
                            reportMessage = "通報を受け付けました"
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .alert("このユーザーをブロックしますか？", isPresented: $showBlock) {
                Button("キャンセル", role: .cancel) {}
                Button("ブロック", role: .destructive) {
                    run {
                        try await store.repository.block(postID: post.id)
                        try await store.didBlock(); dismiss()
                    }
                }
            } message: { Text("この投稿者の今後の速報も表示されなくなります。相手には通知しません。") }
            .alert("速報から削除しますか？", isPresented: $showDelete) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    run {
                        try await store.repository.delete(postID: post.id)
                        store.remove(post.id); dismiss()
                    }
                }
            } message: { Text("習慣の達成・失敗記録は消えません。") }
        }
        // 中身が少ないので半分の高さで開く(ひとことを書くときは引き上げられる)。
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    // MARK: - 投稿

    /// 一覧の行と同じ組み方(アイコン＋「○○おにいさんが」＋結果)に、ひとことと時刻を添える。
    /// 通報・ブロック・削除は常に見せる必要がないので、右下の「…」にまとめる。
    private var postCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                ZakoNewsKindIcon(post: post)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.subjectText).font(.subheadline).foregroundStyle(AppColor.muted)
                    Text(post.resultText).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !post.comment.isEmpty {
                        Text("「\(post.comment)」").font(.subheadline).foregroundStyle(AppColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            HStack {
                Text(post.relativeTime).font(.caption).foregroundStyle(AppColor.muted)
                    .padding(.leading, 52)
                Spacer(minLength: 0)
                moreMenu
            }
        }
        .padding(.leading, 16)
        .padding([.top, .trailing], 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    private var moreMenu: some View {
        Menu {
            if post.isMine {
                Button("速報から削除", systemImage: "trash", role: .destructive) { showDelete = true }
            } else {
                Button("通報する", systemImage: "exclamationmark.bubble") { showReport = true }
                Button("このユーザーをブロックする", systemImage: "nosign", role: .destructive) { showBlock = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.trailing, -10)
        .accessibilityLabel(post.isMine ? "削除などの操作" : "通報・ブロック")
    }

    // MARK: - 応援

    /// 応援は横並びのカプセル。押すと数とその場の見た目が変わる。選んだものは Purple(特別感)で示す。
    private var reactionButtons: some View {
        HStack(spacing: 8) {
            ForEach(ZakoNewsReaction.allCases) { reaction in
                let isSelected = post.myReaction == reaction.rawValue
                Button {
                    run {
                        try await store.repository.react(postID: post.id, reaction: isSelected ? nil : reaction.rawValue)
                        try await reload()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.title)
                        Text("\(post.count(for: reaction))").monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppColor.secondary : AppColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isSelected ? AppColor.secondary.opacity(0.12) : AppColor.surface, in: Capsule())
                    .overlay(Capsule().stroke(isSelected ? AppColor.secondary : AppColor.border, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(reaction.title)、\(post.count(for: reaction))件")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: - ひとこと(自分の投稿のみ)

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ひとこと").font(.headline).foregroundStyle(AppColor.text)
            TextField("ひとことを添える", text: $comment)
                .focused($isCommentFocused)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AppColor.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(alignment: .firstTextBaseline) {
                Text("みんなに公開されます。\(ZakoNewsConfiguration.commentLimit)文字以内・改行とURL不可。個人情報は入力しないでください。")
                    .font(.caption).foregroundStyle(AppColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(comment.unicodeScalars.count)/\(ZakoNewsConfiguration.commentLimit)")
                    .font(.caption.monospacedDigit()).foregroundStyle(AppColor.muted)
            }
            Button {
                run {
                    try await store.repository.comment(postID: post.id, text: comment)
                    try await reload(); reportMessage = "ひとことを保存しました"
                }
            } label: {
                Text("ひとことを保存")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(canSaveComment ? AppColor.primary : AppColor.muted, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSaveComment)
            .padding(.top, 4)
        }
        .padding()
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    private var canSaveComment: Bool {
        comment != post.comment
            && ZakoNewsText.isValid(comment, limit: ZakoNewsConfiguration.commentLimit, allowEmpty: true)
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }; working = true; errorMessage = nil
        Task { @MainActor in
            defer { working = false }
            do { try await action() } catch { errorMessage = "操作できませんでした。接続状況を確認してお試しください。" }
        }
    }
    private func reload() async throws {
        if let fresh = try await store.refreshPost(post.id) { post = fresh } else { dismiss() }
    }
}

struct ZakoNewsSettingsView: View {
    @State private var store = ZakoNewsStore.shared
    @State private var blocks: [ZakoNewsBlock] = []
    @State private var showsOwnPosts = false
    @State private var selectedBlock: ZakoNewsBlock?
    @State private var confirmsUnblock = false
    @State private var errorMessage: String?
    @State private var working = false
    var body: some View {
        List {
            Section {
                Button("自分の速報を見る") { showsOwnPosts = true }
                Text("共有設定は各項目の編集画面で変更できます。速報は7日間表示されます。")
                    .font(.footnote).foregroundStyle(AppColor.muted)
            }
            Section("ブロック中") {
                if blocks.isEmpty { Text("ブロック中のユーザーはいません").foregroundStyle(AppColor.muted) }
                ForEach(blocks) { block in
                    HStack {
                        Text("\(block.display_name)おにいさん"); Spacer()
                        Button("解除") { selectedBlock = block; confirmsUnblock = true }
                    }
                }
            }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(AppColor.error) }
            if working { ProgressView() }
        }
        .disabled(working).navigationTitle("ざこ速報").appScreenBackground()
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $showsOwnPosts) { ZakoNewsFeedSheet(mine: true) }
        .alert("ブロックを解除しますか？", isPresented: $confirmsUnblock) {
            Button("キャンセル", role: .cancel) {}
            Button("解除する") {
                guard let block = selectedBlock else { return }
                Task {
                    working = true
                    defer { working = false }
                    do {
                        try await store.repository.unblock(blockID: block.id)
                        blocks = try await store.repository.blocks()
                    } catch { errorMessage = "解除できませんでした。もう一度お試しください。" }
                }
            }
        }
    }
    private func load() async {
        do { blocks = try await store.repository.blocks(); errorMessage = nil }
        catch { errorMessage = "読み込めませんでした。もう一度お試しください。" }
    }
}
