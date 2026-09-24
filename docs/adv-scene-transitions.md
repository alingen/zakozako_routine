# ADV のカラースライド場面転換

既存の `scene_change` コマンドから使える場面転換です。画面下からメインカラーの面が上がり、全面を覆ったときに背景・立ち絵・本文を交換します。中央で淡いベースカラーの「…」が動き、面が下へ戻ると次の場面が見えます。場面の画像自体は動かしません。

## シナリオから使う

`senarios` シートの対象行を `message_type=action`、`ui_variant=scene_transition`、`command=scene_change` にして、`command_args` セルに以下の JSON を指定します。

```json
{
  "background": "bg_protagonist_entrance",
  "screen_mode": "adv",
  "transition": {
    "type": "colorSlide",
    "duration": 0.70,
    "minimumHold": 0.08
  }
}
```

立ち絵も変更する場合は同じ行の `portrait` 列に次の asset ID を指定します。次のシーンの画像は可能な限り先読みし、準備が終わらない場合だけ全面被覆を延長します。準備済みなら固定の読み込み待ちは追加しません。

| パラメーター | 標準値 | 意味 |
| --- | --- | --- |
| `type` | 明示指定 | `colorSlide` / `crossFade` / `none` |
| `duration` | `0.70` | 準備済みの場合の合計時間（秒） |
| `minimumHold` | `0.08` | 全面を覆った状態の最短時間（秒） |
| `coverDuration` | `0.28` | 上がる動きの時間配分 |
| `revealDuration` | `0.34` | 下がる動きの時間配分 |

`coverDuration` と `revealDuration` は省略できます。指定した場合は配分比として扱い、合計が `duration` になるよう正規化します。標準では `0.28 + 0.08 + 0.34 = 0.70` 秒です。`duration` は0.15〜5秒、`minimumHold` は0〜`duration - 0.1`秒に制限します。

面の色は `AppColor.primary`、中央の点は `AppColor.background` を参照します。色指定はシナリオに不要です。「視差効果を減らす」が有効なら、覆い0.10秒・展開0.12秒の短いフェードに切り替えます。

## 既存コンテンツとの互換性

- `transition` を指定していない場面転換は従来通りです。
- 従来の文字列指定 `"fade"`、`"fade_black"`、`"cut"` の動作は変えません。
- 以前の `pixelSpiral` 指定は互換性のため読み取れますが、表示される演出はカラースライドです。これから追加するシーンでは `colorSlide` を使います。
- 過去ノードから再開するときは演出を再生せず、通常の進行時のみ使います。
- 転換中はシナリオ送り・選択肢を一時停止し、連打による重複転換を受け付けません。

## 本編に指定する例

`middle_001` の `middle_001_212` は、リビングから玄関へ移る既存の場面転換です。CMS のその行の `command_args` を次のようにすると、この箇所で使えます。

```json
{
  "scene_id": "day1_protagonist_entrance",
  "screen_mode": "adv",
  "background": "bg_protagonist_entrance",
  "label": "主人公宅・玄関",
  "transition": {
    "type": "colorSlide",
    "duration": 0.70,
    "minimumHold": 0.08
  }
}
```

前後の本文は `middle_001_211` の「そして完全に日が落ち切った頃、隣の家に母親が帰ってきた。」と、`middle_001_213` の莉央の「じゃ、おじゃましました」です。現在この話には立ち絵指定がないため、立ち絵も確認する場合は旧場面に `portrait_rio_smile`、新場面に `portrait_rio_neutral` などの既存素材を指定します。

## CMS と生成データ

`story_content.generated.json` は Google Sheets から生成されるため、直接編集しません。ネストした `command_args` は既存の同期処理で保持されるので、列の追加は不要です。本編へ反映するときは CMS の対象行を更新してから、通常の `npm --prefix tools/scenario-sync run sync:write` で再生成します。未コミットのシート snapshot や、ほかのコンテンツ変更を上書きするための再生成は行いません。

オフラインの読み取り確認には `npm --prefix tools/scenario-sync run sync:check -- --snapshot` が使えます。現在の snapshot と生成物に既存の差分がある場合は非ゼロ終了するため、この演出の不具合とは区別してください。

## 確認用サンプル

Debug ビルドを `--color-slide-sample` で起動すると、実際の ADV 再生画面を使い、リビングから玄関への転換を繰り返し確認できます。背景・立ち絵・本文を同時に切り替える確認用シナリオは `MesugakiRoutine/Resources/StorySamples/color_slide_sample.json` です。本編の解禁条件や CMS 生成物には影響しません。

追加の確認引数:

- `--color-slide-autoplay`: 約2秒おきに次へ進める。
- `--color-slide-slow-assets`: 画像の先読みを遅らせ、全面被覆中の待機表示を確認する。
- `--color-slide-reduce-motion`: OS 設定を変えず、視差効果軽減時のフェードを確認する。

通常起動と Release ビルドではこれらの引数は無効です。Debug サンプルはメモリー内のストーリー保存領域を使い、読了・進行データを書き換えません。コンソールの計測値はアニメーション実時間、画面更新間隔、Canvas 描画更新頻度の目安であり、実機 GPU の描画完了を保証する値ではありません。

## 実装箇所と確認点

- `MesugakiRoutine/Models/StorySceneTransition.swift`: 設定と演出状態。
- `MesugakiRoutine/Services/StoryPlayer.swift`: 先読み・全面被覆時の交換・入力制限。
- `MesugakiRoutine/Views/StoryPlayer/StorySceneTransitionOverlay.swift`: 画面より下まで伸びる単一の色面を上下移動し、中央の点だけを Canvas で描画。
- `MesugakiRoutine/Views/StoryPlayer/StorySceneAssetPreparation.swift`: 画像準備と描画フレーム待ち。
- `MesugakiRoutineTests/StorySceneTransitionTests.swift`: 時間配分、画面サイズごとの被覆、待機、連打、復帰の検証。

画面サイズが変わっても全面被覆時に端が露出しないこと、背景・立ち絵・本文の交換が被覆中だけに起きること、準備済みの転換で不要な待ち時間がないことを確認します。
