# みんなのざこ速報

## 現在の反映・検証状況

- 2026-09-26: 接続先 `xlboihwjliebpissioxh` のAnonymous Sign-Inを有効化済み。
- 既存public schemaが空であることを確認してからmigrationを適用済み。5テーブルのRLSと、毎時17分の7日経過投稿削除ジョブが有効。
- DB側セキュリティテスト25項目成功。テスト用ユーザー・投稿はロールバック済み。
- 実HTTPで匿名登録、同一ユーザーのセッション更新、投稿・再送、公開Feed、ひとこと、応援追加/重複防止/解除、直接テーブル参照拒否・未認証RPC拒否を確認済み。
- iPhone 13 mini / iOS 17.5向けビルド成功。速報関連テスト10件成功。
- 実機向け（generic iOS / arm64）の署名なしビルドも成功。一度ディスク容量不足になったため、この作業のシミュレーター中間生成物166MBだけを削除し、再ビルドして確認した。
- 全体テスト286件中281件成功、StoryPlayerIntegrationTestsの5件が失敗。
  本番カタログにないevent_large_001 / event_middle_001 / event_middle_002参照、章の話数、訪問ノード期待値の不一致。
  今回の速報変更とは別のテスト/原稿整合性の問題として、既存ファイルは変更していない。
- シミュレーターでHOME実データ表示、3件上限・入れ替え、詳細、応援/解除、共有OFF初期値、初回説明とキャンセル、ブロック後の全投稿除外を確認。
- 確認用の速報4件はソフト削除、確認用ブロックも解除済み。既存習慣データは変更していない。
- 設定画面のブロック解除・自分の投稿編集/削除の実機での一連操作は未確認（API/DBテストでは確認済み）。実機へのインストール・commit・pushは未実施。

## 変更ファイル

- モデル: `Models/ZakoNews.swift`、既存 `Routine.swift` / `BlockedBehavior.swift` / `BlockedBehaviorPreset.swift`。
- 保存/通信: `Repositories/ZakoNewsRepository.swift`、`Services/ZakoNewsStore.swift`、既存 `RoutineRepository.swift` / `BlockedBehaviorRepository.swift`。
- 記録後の共有/編集: `ViewModels/HomeViewModel.swift` / `RoutineEditViewModel.swift`。
- UI: `Views/Home/ZakoNewsViews.swift` / `ZakoNewsSharingSection.swift` / `ZakoBulletinSection.swift` / `HomeView.swift` / `BlockedBehaviorCreateView.swift`、`Views/RoutineEdit/RoutineEditView.swift`、`Views/Settings/SettingsView.swift`。
- 構成/検証: `project.yml`、`MesugakiRoutineTests/ZakoBulletinTests.swift`、`supabase/migrations/202609260001_zako_news.sql`、`supabase/tests/zako_news_security.sql` / `zako_news_http.py`、本書。
- 作業開始前からあるHOME余白・タスク行・交流画面等の変更は保持し、それ以外の未コミット変更を巻き戻していない。

## 構成

- SwiftData の `Routine` / `BlockedBehavior` に `shareToZakoNews` を追加。既存・新規とも初期値OFF。
- 習慣の保存処理は従来の Repository のまま。HomeViewModel が保存成功後にだけ速報を送信する。
- 約束は期間の目標回数に達した時に投稿する。途中の1回ずつでは投稿しない。
- 手動「負けました」は上限未満でも1回ごとに投稿する。Screen Time の自動超過・欠席・履歴読み込み・「負けそう…」は投稿しない。
- SDK: Supabase Swift 2.55.2。npm / `@supabase/server` / サーバー用Secret Keyは不要。
- `ZakoNewsRepository`: 匿名認証、セッション再利用、DB RPC。
- `ZakoNewsStore`: セッション中の表示済みID・小さな再送リスト・HOME表示。
- `ZakoNewsViews`: 一覧スライド、詳細、ひとこと、応援、通報、ブロック、自分の速報削除、ブロック解除。

## Supabaseへの反映

接続先: `xlboihwjliebpissioxh`。アプリには公開可能なPublishable Keyのみを持つ。

1. Authentication → Sign In / Providers → Allow anonymous sign-ins をONに保存。
2. SQL Editorで `supabase/migrations/202609260001_zako_news.sql` を一度実行する。
   既存テーブルの削除・置換はしない。適用済みなら再実行しない。
3. `supabase/tests/zako_news_security.sql` を実行する。テスト用ユーザー・投稿は同じトランザクション内でロールバックされる。
4. Cronの `zako-news-retention` が毎時17分に実行されることを確認する。

CLIを導入して管理する場合は通常の `supabase db push` を使用できる。
SQL Editorから適用済みの場合は、先にCLIのmigration repairでこのバージョンを適用済みとして記録し、二重実行しない。
このプロジェクトでは上記1〜4まで実行済みのため、利用確認のための追加Dashboard作業は不要。

## DBとアクセス制御

| テーブル | 用途 |
| --- | --- |
| zako_profiles | 内部アカウントと公開名の分離 |
| zako_news_posts | 結果の公開用スナップショット・ひとこと・公開/審査状態 |
| zako_news_reactions | 投稿×ユーザーの一意な応援 |
| zako_news_reports | 投稿×通報者の一意な通報 |
| zako_user_blocks | ブロックする側×される側の一意な記録 |

全テーブルでRLS有効。本人限定ポリシーを定義した上で、クライアントのテーブル直接アクセスを禁止する。
公開RPCは `auth.uid()` を必ず検証し、操作対象の所有者をDB側で確認する。
RPCは固定search_path、明示的な実行権限を持つ。認証前のanonロールは実行不可。
Feedにはauth UUID・source_keyを出さない。ブロックは投稿IDから投稿者を解決する。
ブロック解除に使うIDはブロック行のIDであり、投稿者IDではない。

管理者は `is_public=false` または `moderation_status='hidden'/'pending'` で非表示にできる。
自分の速報削除はソフト削除で、再送による復活を防ぐ。元の端末内習慣記録には一切触れない。
7日経過した投稿はFeedから即除外、毎時のCronで物理削除。付随する応援・通報も削除される。

## 二重投稿・通信失敗

- 約束: Routine ID + 現在ルール開始日時 + 集計期間開始日時をsource_keyとし、解除→再達成でも同じ期間の速報を増やさない。
- 敗北: BlockedBehavior ID + 手動記録日時をsource_keyにする。連打は既存の確認UIと上限判定で抑止。
- DBの `(author_id, source_key)` UNIQUEとRPCの既存ID返却により、再送が新規投稿にならない。
- 公開名・タイトルは送信時のスナップショット。変更・公開設定ONによって過去の記録を遡って投稿しない。
- 小規模な配送待ちデータだけUserDefaultsに保持し、起動/再接続または再試行で送信。7日超は破棄。
- 共有OFFや項目削除で未送信を取消。既に送信が始まったもの・共有済みの速報は自分の速報から削除する。
- 記録は同期的に先に保存済みなので、通信失敗は習慣保存の失敗にしない。

## Feed・設定値

`ZakoNewsConfiguration`で件数20・HOME最大3・表示間隔3秒・通信最短60秒・保持7日・ひとこと30文字を管理。
DB側のひとこと制限は `zako_private.comment_limit()`。制限変更時は両方を変更するmigrationを追加する。
文字数はDBと一致させるためUnicode scalar数（絵文字の見た目の数と異なる場合あり）。

Feedは時刻+投稿IDのカーソルページング。表示済みIDはアプリ起動中保持し、表示候補がなければ順序を変えない。
表示候補の上限は40件。HOME表示・通信可能時にまとめて取得し、少ない場合のみ過去ページを補充する。
3秒処理はローカル配列のみ。60秒ごとにキャッシュの公開状態をまとめて検証して新着を取得する。
背景・別画面・入力中・詳細/モーダル中はローテーションを停止する。
新着追加・ブロック後の再読込を除き、Realtimeは使用しない。
他端末での削除や管理者による非表示は最大約60秒のキャッシュ遅延がある。

## 確認項目

1. 新規・既存項目が共有OFF。初回ONだけ説明、キャンセルでOFFのまま。
2. 共有OFFの記録・自動ScreenTime超過・負けそうからは投稿されない。
3. 共有ONの達成、上限3回の1回目の手動敗北で、それぞれ1速報。
4. オフラインでも習慣記録保存→オンラインで再試行→1件だけ投稿。
5. ひとことは任意、30文字・URL・改行検証、同じ投稿を更新。
6. 2つの独立した匿名セッションで応援切替/解除・通報重複防止・ブロック後の現在/将来の除外。
7. 自分の速報を削除しても達成日数・失敗回数が変わらない。
8. HOMEは3件まで、3秒で1件追加、詳細操作中は固定、尽きたら固定。
9. 設定→ざこ速報から自分の投稿/ブロック解除。

DBテストは `supabase/tests/zako_news_security.sql` をSQL Editorで実行する。
実通信テストは明示的に `ZAKO_NEWS_LIVE_TEST=1 python3 supabase/tests/zako_news_http.py` を実行する。
このテストは匿名のテストアカウント1件と確認用投稿4件を作り、終了時に投稿をソフト削除する。
Authアカウント・非公開の投稿スナップショットはDBに残る（投稿は通常の7日保持処理の対象）。
認証トークンはメモリ内だけで扱い、ログ・リポジトリへ保存しない。
UI確認を挟む場合は `--hold-for-ui` を付け、終了時にReturnを入力する。

## リリース前の運用事項

- 自動AI審査、管理画面、Premium差分、通知、Realtimeは未実装（今回のスコープ外）。通報の確認と非表示化は管理者がDashboardで行う。
- 投稿は1アカウント1時間60件で抑制。匿名アカウント作成の濫用対策はSupabase AuthのRate Limitsを確認し、本番公開時はCAPTCHA導入も検討する。
- 匿名セッションを失うと以前の投稿の所有者として操作できない。メール/Apple連携・アカウント復旧は未実装。
- KeychainはSDK標準保存。アプリ削除とKeychainの消去は同義ではない。
- 公開UGC・Supabaseへの送信について、公開前にプライバシーポリシー/利用規約と運用窓口の確認が必要。
