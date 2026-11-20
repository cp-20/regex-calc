# slides

YAPC::Tokyo 2026 LT「正規表現で電卓を作る」の発表資料です。[`index.html`](index.html)1ファイルだけでオフライン動作します。

## 閲覧方法

[`index.html`](index.html)をブラウザで開きます。

| キー | 動作 |
| --- | --- |
| `→` / `Space` / `↓` | 次へ |
| `←` / `↑` | 前へ |
| `f` | 全画面 |
| `n` | ノートを表示 |
| `p` | 発表者ウィンドウ（ノート・タイマー・次のスライド） |

## ビルド方法

```sh
slides/fonts/fetch.sh     # 初回のみ: LINE Seed JP / Monaspace Neon (OFL) を取得
node slides/build.js      # src.html + Perlのトレース + フォントのサブセット → index.html
```

必要な環境:

- `node`（ビルドスクリプト実行）
- `perl`（デモ用トレースの生成）
- `python3`＋`fonttools`・`brotli`（フォントのサブセット化とwoff2埋め込み。`pip install fonttools brotli`）

フォントソースまたは`fonttools`がない場合は、システムフォントにフォールバックしてビルドします。QRコードは[`assets/qr.py`](assets/qr.py)で再生成できます。

### `build.js`の動作

`src.html`内のマーカーを次の内容で展開し、`index.html`を書き出します。

- `@@FONTS@@`: [`fonts/subset.py`](fonts/subset.py)で使用グリフだけをサブセット化したwoff2をデータURIとして埋め込み（LINE Seed JPのRegular / Bold / ExtraBold、Monaspace NeonのRegular / Medium）
- `@@TRACES@@`: `bin/regex-calc --trace`の実行結果
- `@@QR@@`: [`assets/qr.svg`](assets/qr.svg)
- `@@ICON@@`: [`assets/icon.png`](assets/icon.png)のデータURI

また、ビルド時に画面表示テキストのスペース検査（lint）が走ります。日本語と英数字・記号の間にスペース（`x 1 文字`など）があるとビルドが失敗します（スピーカーノートとコメントは対象外）。

## 書き方

- `src.html`の`frame({...})`1つが1クリック分です。
- 連続する2つのフレームで同じ`data-k`を持つ要素は位置・大きさ・色が補間され、それ以外はフェードで入れ替わります。
- `data-from`を付けると、前のフレームのその要素の位置から出てきます。
- `call`は指定したグリフの上（`below: true`で下）に吹き出しを重ねます。
- `hl`を付けたグリフは、隣り合うもの同士で1本のマーカーになります。マーカーは字面に合わせ、上下左右の余白をそろえます。
- `w: true`を付けたマーカーだけがワイプで出ます（視線誘導用）。ほかはフェードです。`mark`で任意の要素にマーカーを引けます。
- `fly`は前のフレームの要素のコピーを、新しい要素の真下へ飛ばします。
- `pre`を指定すると、前のフレームにない要素（`preKeys`）が、指定したフレームでの位置から動きます。
- デモは`bin/regex-calc --trace`の出力をビルド時に埋め込んで再生します。

## フォントおよびアセットのライセンス

- `index.html`に埋め込まれているフォントは、以下のSIL Open Font License 1.1フォントのサブセットです。ライセンス全文は[`fonts/OFL-LINESeedJP.txt`](fonts/OFL-LINESeedJP.txt)および[`fonts/OFL-MonaspaceNeon.txt`](fonts/OFL-MonaspaceNeon.txt)を参照してください。
  - **LINE Seed JP**（© LY Corporation）→ `Deck Sans`にリネーム
  - **Monaspace Neon**（© 2023 GitHub、Reserved Font Name "Monaspace"）→ `Deck Mono`にリネーム
- SIL OFL 1.1では改変版（サブセットを含む）にReserved Font Nameを使用できないため、[`fonts/subset.py`](fonts/subset.py)でフォント名を変更し、著作権・ライセンスレコードを保持しています。
- フォントバイナリ自体はリポジトリに含めておらず、[`fonts/fetch.sh`](fonts/fetch.sh)で取得します。
- [`assets/icon.png`](assets/icon.png)は作者のアバター画像であり、リポジトリのMIT Licenseの対象外です。
