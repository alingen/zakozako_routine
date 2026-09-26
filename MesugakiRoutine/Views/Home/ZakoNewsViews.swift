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
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if posts.isEmpty && !loading { Text("まだ速報はありません").foregroundStyle(AppColor.muted) }
                ForEach(posts) { post in
                    Button { selected = post } label: { ZakoNewsRow(post: post) }.buttonStyle(.plain)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(AppColor.error) }
                if hasMore && !loading { Button("さらに読み込む") { Task { await load(reset: false) } } }
            }
            .appScreenBackground().navigationTitle(mine ? "自分の速報" : "みんなのざこ速報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .refreshable { await load(reset: true) }
            .task { await load(reset: true) }
            .sheet(item: $selected, onDismiss: { Task { await load(reset: true) } }) { post in ZakoNewsDetailView(post: post) }
        }.presentationDragIndicator(.visible)
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true
        if reset { posts = []; cursor = nil; hasMore = true }
        defer { loading = false }
        do {
            let page = try await store.repository.feed(before: reset ? nil : cursor, ids: nil, mine: mine)
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.filter { !known.contains($0.id) })
            cursor = page.last; hasMore = page.count == ZakoNewsConfiguration.batchSize; errorMessage = nil
        } catch { errorMessage = "速報を読み込めませんでした。もう一度お試しください。" }
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

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(post.line).font(.headline); if !post.comment.isEmpty { Text(post.comment) } }
                Section("応援") {
                    ForEach(ZakoNewsReaction.allCases) { reaction in
                        Button {
                            run {
                                try await store.repository.react(postID: post.id,
                                    reaction: post.myReaction == reaction.rawValue ? nil : reaction.rawValue)
                                try await reload()
                            }
                        } label: {
                            HStack {
                                Text(reaction.title); Spacer()
                                Text("\(post.count(for: reaction))").monospacedDigit()
                                if post.myReaction == reaction.rawValue { Image(systemName: "checkmark.circle.fill") }
                            }
                        }.tint(post.myReaction == reaction.rawValue ? AppColor.primary : AppColor.text)
                    }
                }
                if post.isMine {
                    Section {
                        TextField("ひとことを添える", text: $comment)
                        Text("\(comment.unicodeScalars.count)/\(ZakoNewsConfiguration.commentLimit)").font(.caption).foregroundStyle(AppColor.muted)
                        Button("ひとことを保存") {
                            run {
                                try await store.repository.comment(postID: post.id, text: comment)
                                try await reload(); reportMessage = "ひとことを保存しました"
                            }
                        }.disabled(!ZakoNewsText.isValid(comment, limit: ZakoNewsConfiguration.commentLimit, allowEmpty: true))
                    } header: { Text("ひとこと") } footer: {
                        Text("みんなに公開されます。\(ZakoNewsConfiguration.commentLimit)文字以内・改行とURL不可。個人情報は入力しないでください。")
                    }
                    Section { Button("速報から削除", role: .destructive) { showDelete = true } }
                } else {
                    Section {
                        Button("通報する") { showReport = true }
                        Button("このユーザーをブロックする", role: .destructive) { showBlock = true }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppColor.error).font(.footnote) }
                if let reportMessage { Text(reportMessage).font(.footnote).foregroundStyle(AppColor.muted) }
                if working { ProgressView() }
            }
            .disabled(working).appScreenBackground().navigationTitle("ざこ速報").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.disabled(working) } }
            .onAppear { comment = post.comment }
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
        }.presentationDragIndicator(.visible)
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
