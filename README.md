# regex-calc

整数の四則演算（`+` `-` `*` `/`）と括弧（入れ子可・負数対応）を、Perlの`s///`置換だけで計算する電卓です。YAPC::Tokyo 2026のLT「正規表現で電卓を作る」（cp-20 / [@__cp20__](https://x.com/__cp20__)）のために作りました。

```sh
$ perl bin/regex-calc '(3+6)*8'
72  (5 s/// passes)
```

`--trace`を付けると、各`s///`パスのパターンと変換前後の文字列を確認できます（長い`x`の連続は`x{12}`のように省略表示されます）。

```sh
$ perl bin/regex-calc --trace '(1+2)*4'
...
#3 add
  pattern: (?^:\+\#)
  replace:
  flags  : g
  before : #x+#xx
  after  : #xxx
#4 mul+add
  pattern: (?^:(?<![x#])(\#)(?=x*+\*\#)|\Gx(?=x*+\*\#(x*+))|\*\#x*+|\+\#)
  replace: $1$2
  flags  : g
  before : #xxx*#xxxx
  after  : #x{12}
...
result: 12  (5 s/// passes)
```

## 仕組み

数値を`x`の個数（単項表現）に変換して計算します。`3`は`#xxx`、`-3`は`-#xxx`です。

たとえば`3+4`は次の流れで計算します。

```text
3+4  →  #xxx+#xxxx  →  #xxxxxxx  →  7
```

パイプライン全体は次の5段階です。

1. **10進→単項**: 式の末尾に`s/$/…/`で変換表を付け、`/g`の表引き1パスで各桁を`x`の列へ展開する（5〜8桁は4桁ごとの塊に分けて畳む）
2. **括弧**: 最も内側の`\(([^()]*)\)`から順に評価し、結果を元の位置へ戻す
3. **乗除**: `*`と`/`を処理する（乗算はペア単位のトーナメント、除算は10000/100/1ブロックの3段先読み＋後方参照）
4. **加減**: 全項が正なら`s/\+#//g`の1パス。負項を含む場合は式を4つ複製して正項と負項に分け、後方参照で差を取る（項数に依らず3パス）
5. **単項→10進**: 桁数を`m//`の形状テストで選び、分岐リセット`(?|…)`で10進表記へ戻す

計算の効率化と線形時間維持のために、次のPerl正規表現機能を使っています。

| 機能 | 使いどころ |
| --- | --- |
| 先読みによる表引き | 末尾に付けた変換表`@0123456789#|…`を先読みで参照して桁変換 |
| `\G`連鎖 | 左オペランド先頭`#`で1回だけ`*`の有無を判定し、後続の`x`を連鎖させてO(n²)を回避 |
| 所有量指定子`x*+`、`[^@]*+` | 失敗する先読みでの無駄なバックトラックを抑止 |
| 分岐リセット`(?\|…)` | 単項→10進で桁ごとの10分岐を同じキャプチャ番号に揃え、置換文字列を固定 |
| 再帰`(?&name)`＋`(?(DEFINE)…)` | `calc_fixed`の文法・境界チェック |
| 固定長の負の後読み`(?<![x#)])` | 二項`-`と単項`-`の区別 |
| `qr//`事前コンパイル | パターンの再コンパイルを防止 |

## ズルをしないルール

Perl本体に許されるのは、定数からのパターン組み立て、`m//`による形状テスト、括弧部分式などの結果の貼り替え、パス回数の計上、入力検証だけです。値の演算はすべてカウント対象の`s///`で行います。

禁止事項の例:

- `/e`、`/ee`、`(?{})`、`(??{})`、`(*{})`、`eval`
- `tr///`、`y///`、`length`、`sprintf`、`substr`、`pos`、`Math::Big*`
- 数値比較・数値演算代入・`$COUNT++`以外のインクリメント
- パターンや置換文字列への入力値・キャプチャ変数・ローカル変数の埋め込み（定数と`$1..$99`のみ可）
- 作業文字列への定数テキストの連結（表や予備の付加もカウント対象の`s///`で行う）

このルールは[`t/no_cheat.t`](t/no_cheat.t)と[`t/lib/NoCheat.pm`](t/lib/NoCheat.pm)による`lib/`の静的解析で機械的に検査しています。`t/no_cheat.t`では検査器自身が典型的なズルを確実に検出できることもテストしています。

## 使い方

Perlのコアモジュールのみで動作し、外部CPANモジュールは不要です。

### CLI

```sh
perl bin/regex-calc '(3+6)*8'              # 結果とs///の回数を表示
perl bin/regex-calc --trace '(1+2)*4'      # 各s///パスの詳細を表示
perl bin/regex-calc --fixed '(1+2)*(3+4)'  # 固定回数モード（常に6回）
perl bin/regex-calc --help                 # ヘルプ表示（-hも可）
```

### モジュールAPI

```perl
use lib 'lib';
use RegexCalc qw(calc calc_fixed);

my ($result, $passes) = calc('(3+6)*8');        # ('72', 5)
my ($r2, $p2)         = calc_fixed('(1+2)*4');  # ('12', 6)
```

`calc`と`calc_fixed`はいずれも`($result, $passes)`の2要素リストを返します。

### 固定回数モード（`calc_fixed`）

文法を制限する代わりに、契約内の任意の入力を常に**6回**の`s///`（表付加→単項化→乗除→括弧内加算＋括弧除去→乗除＋加算→10進化）で計算します。

契約:

- 演算子は`+` `*` `/`のみ（`-`は不可）、数値は4桁以内の非負整数
- 各項に含まれる`*`または`/`は高々1個
- 括弧の深さは1段まで、平坦な式の`+`は6個以内
- 空白除去後の式は32文字以内、計算結果は10⁸未満

### エラー

不正な入力や契約外の式は`die`で例外を送出します。

| メッセージ | 発生条件 |
| --- | --- |
| `Invalid characters` | 許可されていない文字を含む、または空文字列 |
| `Invalid expression` | 構文エラー |
| `Division by zero` | 0による除算 |
| `Number too large` | `calc`で9桁以上の数値を含む |
| `Subtraction is not supported by calc_fixed` | `calc_fixed`で`-`を含む |
| `Out of fixed-mode bounds` | `calc_fixed`の契約（桁数・括弧深さ・文字数など）を超過 |
| `Result too large for fixed mode` | `calc_fixed`の結果が10⁸以上 |

## テスト

```sh
prove -l t
```

| ファイル | 内容 |
| --- | --- |
| [`t/01_basic.t`](t/01_basic.t) | 基本演算・優先順位・符号・パス回数上限・エラー系 |
| [`t/02_differential.t`](t/02_differential.t) | 乱択式や符号全組み合わせをリファレンス実装（[`t/lib/Reference.pm`](t/lib/Reference.pm)）と照合 |
| [`t/03_perf.t`](t/03_perf.t) | 入力を4倍にしたときの所要時間比から線形時間（O(n²)でないこと）を検証 |
| [`t/04_fixed.t`](t/04_fixed.t) | `calc_fixed`の6パス固定・乱択照合・エラー系 |
| [`t/no_cheat.t`](t/no_cheat.t) | `lib/`に対するズル禁止ルールの静的検査と検査器自身のテスト |

CI（`.github/workflows/test.yml`）で複数のPerlバージョンに対する`prove`実行とスライドのビルドを行います。

## ベンチマーク

```sh
perl bench/bench.pl --md
```

実行例（`perl 5.38.2, linux`、所要時間は環境依存）:

| 式 | 結果 | `s///` の回数 | 1回あたり (µs) |
| --- | ---: | ---: | ---: |
| `(3+6)*8` | 72 | 5 | 40.2 |
| `100-2*60+5` | -15 | 7 | 134.5 |
| `1+2+3+4+5+6+7+8+9` | 45 | 4 | 47.6 |
| `1-2-3-4-5-6-7-8-9` | -43 | 6 | 98.9 |
| `(1+2)*(3+4)` | 21 | 6 | 48.0 |
| `((1+2)*3+4)*2` | 26 | 6 | 104.5 |
| `8-10*-33` | 338 | 7 | 131.6 |
| `999*999` | 998001 | 4 | 2220 |
| `123456` | 123456 | 5 | 1438 |
| `100000+1` | 100001 | 6 | 1323 |
| `100000/2` | 50000 | 7 | 4942 |

## スライド

YAPC::Tokyo 2026 LTの発表資料は[`slides/index.html`](slides/index.html)に単一HTMLファイルとして同梱しています（オフライン動作対応）。閲覧方法やビルド手順は[`slides/README.md`](slides/README.md)を参照してください。

## ディレクトリ構成

```text
.
├── LICENSE
├── README.md
├── bench/
│   └── bench.pl          # パス回数・実行時間ベンチマーク
├── bin/
│   └── regex-calc        # CLIエントリポイント
├── lib/
│   └── RegexCalc.pm      # 電卓本体
├── slides/
│   ├── README.md         # スライドの閲覧・ビルド手順
│   ├── build.js          # 単一HTMLビルドスクリプト
│   ├── index.html        # ビルド済みスライド（オフライン動作）
│   ├── src.html          # スライドソース
│   ├── assets/           # アイコン・QRコード生成スクリプト
│   └── fonts/            # フォント取得・サブセット化スクリプトとOFLライセンス
└── t/
    ├── 01_basic.t
    ├── 02_differential.t
    ├── 03_perf.t
    ├── 04_fixed.t
    ├── no_cheat.t
    └── lib/
        ├── NoCheat.pm    # ズル禁止の静的検査器
        └── Reference.pm  # 差動テスト用リファレンス実装
```

## ライセンス

- コードおよびスライドソース: MIT License（[`LICENSE`](LICENSE)）
- `slides/index.html`に埋め込まれたフォント: SIL Open Font License 1.1（[`slides/fonts/OFL-LINESeedJP.txt`](slides/fonts/OFL-LINESeedJP.txt)、[`slides/fonts/OFL-MonaspaceNeon.txt`](slides/fonts/OFL-MonaspaceNeon.txt)）。LINE Seed JP（© LY Corporation）およびMonaspace Neon（© 2023 GitHub、Reserved Font Name "Monaspace"）のサブセットであり、OFLのReserved Font Name規定に従い`Deck Sans` / `Deck Mono`にリネームしています。フォントバイナリ自体はリポジトリに含めず、`slides/fonts/fetch.sh`で取得します。
- [`slides/assets/icon.png`](slides/assets/icon.png): 作者のアバター画像であり、MIT Licenseの対象外です。
