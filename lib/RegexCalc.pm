package RegexCalc;
# regex-calc: 整数式の計算を s/// だけで行う電卓。
# Perl は「パターンの組み立て・文字列の切り貼り・パス回数の数え上げ」にだけ使う。
# 値の演算 (加算・乗算・除算・桁変換) はすべて tick; ... s/// の 1 行で行い、1 回ごとに数える。
#
# 表現: n>=0 -> '#' . 'x' x n   /   n<0 -> '-#' . 'x' x |n|
use strict;
use warnings;
no warnings 'uninitialized';    # 参加しなかった $N は空文字として展開したい
use Exporter 'import';
our @EXPORT    = qw(calc);
our @EXPORT_OK = qw(calc calc_fixed);

our $COUNT     = 0;    # s/// の実行回数
our $TRACE;            # CODE ref: ($name, $re, $before, $after, $replacement, $flags)
my  @LAST;

my  @REPL;
sub tick { $COUNT++; if ($TRACE) { @LAST = @_[0 .. 2]; @REPL = @_[3, 4] } return }    # 回数 +1 (s/// の直前に必ず呼ぶ)
sub tock { $TRACE->(@LAST, $_[0], @REPL) if $TRACE; return }  # トレース用 (after)

# ===========================================================================
# BUILD-TIME CONSTANTS  (入力に依存しない定数だけから組み立てる)
# ===========================================================================

# 対応表。式の末尾に 1 回だけ s/$/$TBL_x/ (数える 1 パス) で付け、以降のパスは表に触れずに運ぶ。
#   '@0123456789#|<place><digit>:<run>|...'  (先頭の 0123456789 は単項 -> 10 進が読む数字の並び)
# run は digit*10^place 個の x (place 3 は place 2 の表を 10 倍して使う)。
sub _table {
    my ($top) = @_;
    my $t = '@0123456789#';
    for my $q (reverse 0 .. $top) {
        for my $d (0 .. 9) {
            $t .= "|$q$d:" . (('x' x $d) x (10 ** $q));    # const-x
        }
    }
    return $t;
}
my $TBL_0 = _table(0);    # 1 桁用
my $TBL_A = _table(1);    # 1-2 桁用
my $TBL_B = _table(2);    # 3-4 桁用 (と 5-8 桁の下位 4 桁用)

# 桁位置 q の数字を拾うブランチ。$top は最上位の位置、$chunked なら 4 桁ごとの塊に分ける。
sub _unary_re {
    my ($top, $chunked) = @_;
    my $head = '(?:(?<!\d)(?=\d)'
             . ($chunked ? '|(?=\d(?:\d{4})*+\d{3}(?!\d))' : '')    # 塊の先頭にも '#'
             . ')(?=[^@]*+@\d{10}(#))';                               # $1 = '#'
    my @alt;
    for my $q (0 .. $top) {
        my $dg   = 2 + 2 * $q;                                         # 数字の群番号 (値は次の群)
        my $key  = $q < 2 ? $q : 2;
        my $rest = $q ? "\\d{$q}" : '';    # const-x
        $rest = "(?:\\d{4})*+$rest" if $chunked;
        push @alt, "(\\d)(?=$rest(?!\\d))(?=[^\@]*+\@.*\\|$key\\g{$dg}:(x*))";    # const-x
    }
    return qr/$head|@{[ join '|', @alt ]}|(\@.*\z)/;    # const-x   (最後の群 = 表。そのまま写す)
}
my $RE_0  = _unary_re(0, 0);
my $RE_A  = _unary_re(1, 0);
my $RE_B  = _unary_re(3, 0);
my $RE_CH = _unary_re(3, 1);

# 5-8 桁: 上位塊 '#A' と下位塊 '#B' を 1 パスで A*10^4+B に畳む。
#   先頭 '#'、続く x は \G で連鎖し、表の直前に s/\@/$RESERVOIR/ で差した予備 '!xxxx...' (x 10000 個) を 1 つずつ貼り付ける。
my $APPEND = qr/$/;     # 表・予備を足す s/// のパターン (入力は空白除去済みなので末尾の改行はない)
my $AT     = qr/\@/;
my $RESERVOIR = '!' . ('x' x 10000) . '@';    # const-x
my $FOLD = qr/(?<![x#])(\#)(?=x*\#)|\Gx(?=[^!]*+!(x+))|(?<=[x#])\#(x*)|!x+(?=\@)/;

# 単項 -> 10 進: k 桁を 1 パスで読む。x が 10^k 個以上あれば 10^k 個ごとに 1 個へ畳む。
#  各桁は 'd 個の (x{10^q}) ブロック' を最大側から試す分岐リセット (?|...) で拾い、
#  数字そのものは式末尾の表 ('@0123456789...') から .{d} で取り出す。
#  $k = 7 は「6 桁読み + まだ続きがある」パス: 表を残す ($9)。ほかは最後のパスで表を食う。
sub _dec_re {
    my ($k) = @_;
    my $more = $k eq 7;
    $k = 6 if $more;
    my $B   = 10 ** $k;                                          # const-x
    my $src = "\\#|(?=(x))x{$B}|";    # const-x   (先頭の '#' は捨てる)
    for my $q (reverse 0 .. $k - 1) {
        my $b   = 10 ** $q;                                      # const-x
        my @alt = map {
            my $d = $_;
            $d ? "(?:x{$b}){$d}(?=[^\@]*+\@.{$d}(\\d))" : "(?=[^\@]*+\@(\\d))"    # const-x
        } reverse 0 .. 9;
        $src .= '(?|' . join('|', @alt) . ')';
    }
    $src .= '()' x (6 - $k);                                     # const-x: 群番号を揃える
    $src .= $more ? '(\d*)(\@.*\z)' : '(\d*)\@.*\z';
    return qr/$src/;    # const-x
}
my @DEC;    # 遅延構築 (使う k だけコンパイル)
sub _dec { $DEC[$_[0]] //= _dec_re($_[0]) }

# 掛け算 (互いに素なペア/連鎖のトーナメント 1 パス)。符号は先頭で決め、左オペランドの各 x を右オペランドへ置換する。
#   $1 neg*neg -> '#'   $2 *pos -> 左の符号を保つ   $4$3 pos*neg -> '-#'
#   $5 左の x 1 個 -> 右の run   $6 演算子と右オペランドを削除 (次が '*' ならそれは残す)
#   左オペランドの先頭 ('#') で 1 回だけ「後ろに '*' があるか」を判定し、以降の x は \G で連鎖させる。
#   (x ごとに先読みすると、'*' の無い長い x 列で O(n^2) になる)
my $MUL = qr/
    (?<![x#)])-(\#)(?=x*+\*-\#)
  | (?<![x#)])(-?\#)(?=x*+\*\#)
  | (?<![x#)])(\#)(?=x*+\*(-)\#)
  | \Gx(?=x*+\*-?\#(x*+))
  | \*-?\#x*+(?:(\*)(?=-?\#))?
/x;
my $MUL_PAIR   = qr/(?<![x#)])-?\#x*\*-?\#/;     # 乗算ペアがあるかの形状テスト
my $FAST       = qr/(?<![x#])(\#)(?=x*+\*\#)|\Gx(?=x*+\*\#(x*+))|\*\#x*+|\+\#/;   # 非負・各項 '*' 高々 1 個: 乗算と加算を 1 パスで ($1$2)
my $FAST_SHAPE = qr/^\#x*(?:\*\#x*)?(?:\+\#x*(?:\*\#x*)?)*\z/;
my $SUM_SHAPE  = qr/^\#x*(?:\+\#x*)+\z/;

# 符号付き和: 区切りの違う 4 つの写し '#S1-|S2;#S3-!S4' を作り、写し 1 と 4 では正項、2 と 3 では負項の x だけを残す。
#   '#P-|N;#N-!P' になる (P, N は正項・負項の x 列)。
my $COPY4   = qr/^(.*)\z/s;    # 式全体を 4 つの写しにする (定数のつなぎ文字つき)
my $SPLIT   = qr/(?:\+|--)\#(?=[^|;!]*+(?:\||\z))(x*+)|(?:\+-|-)\#(?=[^|;!]*+(?:\||\z))x*+|(?:\+|--)\#x*+|(?:\+-|-)\#(x*+)/;
# P-N の解決。後方参照だけで比べる (短い側を possessive に丸ごと取って、長い側の先頭と \N で 1 回比べるだけ)。
#   P<N : '#P-|N' の先頭 P 個を消す。N の余り (1 個以上) が残る -> '-#' + 余り。後ろの写しは捨てる。
#   P>=N: '#N-!P' の先頭 N 個を消す。P の余りが残る            -> '#' + 余り。前の写しは捨てる。
my $RESOLVE = qr/
    ^(?=\#x*+(-)\|)(\#)(x*+)-\|\3(x++);.*+\z
  | ^\#[^;]*+;(\#)(x*+)-!\6(x*+)\z
/xs;
my $SUM_OK  = qr/^-?\#x*(?:(?:\+-|--|[+-])\#x*)*\z/;

my $UNARY_PAIR = qr/(?<![x#)])--/;

# ===========================================================================
# 1. 10 進 -> 単項
# ===========================================================================
sub _to_unary {
    my ($e) = @_;
    return $e unless $e =~ /[0-9]/;
    if ($e =~ /[0-9]{5}/) {
        if ($e =~ /(?<![0-9])0[0-9]/) { tick('strip-zeros', qr/(?<![0-9])0+(?=[0-9])/, $e, q{}, 'g'); $e =~ s/(?<![0-9])0+(?=[0-9])//g; tock($e); }
        die "Number too large\n" if $e =~ /[0-9]{9}/;
    }
    # 表は式の長さ(桁数)に合う 1 つを、形状テストで選んで 1 回だけ付ける (s/\z/表/)。
    my $s = $e;
    if ($e =~ /[0-9]{5}/) {
        tick('append-table', $APPEND, $s, $TBL_B, '');
        $s =~ s/$APPEND/$TBL_B/;
        tock($s);
        tick('to-unary(chunk)', $RE_CH, $s, q{$1$3$5$7$9$9$9$9$9$9$9$9$9$9${10}}, 'g');
        $s =~ s/$RE_CH/$1$3$5$7$9$9$9$9$9$9$9$9$9$9${10}/g;
        tock($s);
        if ($s =~ /\#x*\#/) {
            tick('append-reservoir', $AT, $s, $RESERVOIR, '');
            $s =~ s/\@/$RESERVOIR/;
            tock($s);
            tick('fold-chunks', $FOLD, $s, q{$1$2$3}, 'g');
            $s =~ s/$FOLD/$1$2$3/g;
            tock($s);
        }
    }
    elsif ($e =~ /[0-9]{3}/) {
        tick('append-table', $APPEND, $s, $TBL_B, '');
        $s =~ s/$APPEND/$TBL_B/;
        tock($s);
        tick('to-unary', $RE_B, $s, q{$1$3$5$7$9$9$9$9$9$9$9$9$9$9${10}}, 'g');
        $s =~ s/$RE_B/$1$3$5$7$9$9$9$9$9$9$9$9$9$9${10}/g;
        tock($s);
    }
    elsif ($e =~ /[0-9]{2}/) {
        tick('append-table', $APPEND, $s, $TBL_A, '');
        $s =~ s/$APPEND/$TBL_A/;
        tock($s);
        tick('to-unary', $RE_A, $s, q{$1$3$5$6}, 'g');
        $s =~ s/$RE_A/$1$3$5$6/g;
        tock($s);
    }
    else {
        tick('append-table', $APPEND, $s, $TBL_0, '');
        $s =~ s/$APPEND/$TBL_0/;
        tock($s);
        tick('to-unary', $RE_0, $s, q{$1$3$4}, 'g');
        $s =~ s/$RE_0/$1$3$4/g;
        tock($s);
    }
    return $s;
}

# ===========================================================================
# 2. 単項 -> 10 進
# ===========================================================================
sub _from_unary {
    my ($s) = @_;
    $s =~ /^-?\#x*\@/ or die "Invalid expression\n";
    my $k;
    do {
        # 桁数は x の個数を形状テストで選ぶ (長さの計算はしない)。符号と先頭の '#' は読み飛ばす。
        $k = $s =~ /^-?\#?x{1000000}/ ? 7 : $s =~ /^-?\#?x{100000}/ ? 6 : $s =~ /^-?\#?x{10000}/ ? 5 : $s =~ /^-?\#?x{1000}/ ? 4
           : $s =~ /^-?\#?x{100}/ ? 3 : $s =~ /^-?\#?x{10}/ ? 2 : 1;
        my $re = _dec($k);
        tick("to-decimal(k=$k)", $re, $s, q{$1$2$3$4$5$6$7$8$9}, 'g');
        $s =~ s/$re/$1$2$3$4$5$6$7$8$9/g;
        tock($s);
    } while ($k eq 7);
    # 4 桁ずつ読むので先頭に 0 が残る。数字を読み出すだけ (文字は足さない)。
    $s =~ /^(-?)0*(\d+)\z/ or die "Invalid expression\n";
    return $2 eq '0' ? '0' : "$1$2";
}

# ===========================================================================
# 3. 乗除
# ===========================================================================
# 除算: パターンは定数。除数 B は先読みで読み、後方参照でブロック長として使う。
# ブロックごとに '/' まで走査し直すと O(n^2) になるので、10000 ブロック / 100 ブロック / 1 ブロックの 3 段を
# この順に試す。各段が出す x の個数 (10000 / 100 / 1) は式末尾の予備 '@xxxx...' から先読みで拾う。
# 小さい除算に 10KB の予備を付けないよう、予備の長さは x の連続の形状テスト (/x{100}/ /x{10000}/) で 3 通りから選ぶ。
my $DIV_RESERVE_M = '@' . ('x' x 100);      # const-x
my $DIV_RESERVE_L = '@' . ('x' x 10100);    # const-x
#   小さい除算 (x が 100 個未満) は予備なしで、段 3 だけで足りる。大きい除算は予備を s/\z/予備/ (数える) で付ける。
#   符号: 結果が負 (被除数だけ負 / 除数だけ負) で商が 0 でないときだけ '-' を残す (または先頭に出す)。
#     商が 0 でない = 被除数の先頭が除数 (B) と同じだけ x を持つ (\g{8} / \g{10})。
my $DIVIDE = qr/
    (?=x*+\/-?\#(x++)\@x{100}(x{10000}))(?:\1){10000}
  | (?=x*+\/-?\#(x++)\@(x{100}))(?:\3){100}
  | (?=(x)x*+\/-?\#(x++)(?:\@|\z))\6
  | ^(-)(?=\#(?=x*+\/\#(x++)(?:\@|\z))\g{8})
  | ^(?=\#(?=x*+\/(-)\#(x++)(?:\@|\z))\g{10})
  | ^-
  | x++(?=\/)
  | \/-?\#x++(?:\@x*+)?\z
/x;

sub _divide {
    my ($pair) = @_;
    $pair =~ /^-?\#x*\/-?\#(x*)\z/ or die "Invalid expression\n";
    die "Division by zero\n" unless $1 =~ /x/;
    my $out = $pair;
    if ($pair =~ /x{100}/) {
        if ($pair =~ /x{10000}/) { tick('append-reserve', $APPEND, $out, $DIV_RESERVE_L, ''); $out =~ s/$APPEND/$DIV_RESERVE_L/; tock($out); }
        else                     { tick('append-reserve', $APPEND, $out, $DIV_RESERVE_M, ''); $out =~ s/$APPEND/$DIV_RESERVE_M/; tock($out); }
    }
    tick('divide', $DIVIDE, $out, q{$2$4$5$7$9}, 'g');
    $out =~ s/$DIVIDE/$2$4$5$7$9/g;
    tock($out);
    return $out;
}

sub _muldiv {
    my ($s) = @_;
    return $s unless $s =~ m{[*/]};
    if ($s !~ m{/}) {
        while ($s =~ /\*/) {
            if ($s =~ $FAST_SHAPE) {
                tick('mul+add', $FAST, $s, q{$1$2}, 'g');
                $s =~ s/$FAST/$1$2/g;
                tock($s);
                return $s;
            }
            last unless $s =~ $MUL_PAIR;
            tick('mul', $MUL, $s, q{$1$2$4$3$5$6}, 'g');
            $s =~ s/$MUL/$1$2$4$3$5$6/g;
            tock($s);
        }
    }
    else {
        while ($s =~ /^(.*?)(?<![x)#])(-?\#x*[*\/]-?\#x*)(.*)\z/s) {
            my ($pre, $pair, $post) = ($1, $2, $3);
            my $out;
            if ($pair =~ /\*/) {
                $out = $pair;
                tick('mul', $MUL, $out, q{$1$2$4$3$5$6}, 'g');
                $out =~ s/$MUL/$1$2$4$3$5$6/g;
                tock($out);
            }
            else {
                $out = _divide($pair);
            }
            $s = $pre . $out . $post;
        }
    }
    die "Invalid expression\n" if $s =~ m{[*/]};
    return $s;
}

# ===========================================================================
# 4. 加減
# ===========================================================================
sub _addsub {
    my ($s) = @_;
    die "Invalid expression\n" unless $s =~ $SUM_OK;
    return $s if $s =~ /^-?\#x*\z/;    # 項が 1 つ
    if ($s =~ $SUM_SHAPE) {
        tick('add', qr/\+\#/, $s, q{}, 'g');
        $s =~ s/\+\#//g;
        tock($s);
        return $s;
    }
    # 4 つの写しを作る: '#P-|N;#N-!P' (P は正項の和、N は負項の和の x 列)
    my $w = $s;
    tick('copy-x4', $COPY4, $w, q{#+$1-|+$1;#+$1-!+$1}, '');
    $w =~ s/$COPY4/#+$1-|+$1;#+$1-!+$1/;
    tock($w);
    tick('split-plus/minus', $SPLIT, $w, q{$1$2}, 'g');
    $w =~ s/$SPLIT/$1$2/g;
    tock($w);
    tick('resolve', $RESOLVE, $w, q{$1$2$4$5$7}, 'g');
    $w =~ s/$RESOLVE/$1$2$4$5$7/g;
    tock($w);
    return $w;
}

# ===========================================================================
# 5. 括弧なしの式
# ===========================================================================
sub _flat {
    my ($s) = @_;
    if ($s =~ $UNARY_PAIR) {
        tick('unary-minus-pairs', $UNARY_PAIR, $s, q{}, 'g');
        $s =~ s/$UNARY_PAIR//g;
        tock($s);
    }
    $s = _muldiv($s);
    $s = _addsub($s);
    die "Invalid expression\n" unless $s =~ /^-?\#x*\z/;
    return $s;
}

# ===========================================================================
# 6. エントリポイント
# ===========================================================================
sub calc {
    my ($expr) = @_;
    local $COUNT = 0;
    die "Invalid characters\n" unless defined $expr && $expr =~ /^[0-9\s()+*\/-]+\z/;
    if ($expr =~ /\s/) { tick('strip-space', qr/\s+/, $expr, q{}, 'g'); $expr =~ s/\s+//g; tock($expr); }

    my $s = _to_unary($expr);
    # 最も内側の括弧から。文字列の貼り替えは構造操作で、数えない。
    while ($s =~ /^(.*?)\(([^()]*)\)(.*)\z/s) {
        my ($pre, $in, $post) = ($1, $2, $3);
        $s = $pre . _flat($in) . $post;
    }
    # 表 ('@' 以降) は運ぶだけ。式の部分だけを計算して元の場所に戻す。
    $s =~ /^([^@]*)(.*)\z/s;
    my ($body, $table) = ($1, $2);
    $s = _flat($body) . $table;
    my $r = _from_unary($s);
    return ($r, $COUNT);
}

# ===========================================================================
# 7. 固定回数モード (+ * / と括弧 1 段, 非負)。入力が契約内なら s/// は常に 6 回。
#   契約: 数は 4 桁以内 / 各項に * か / は高々 1 個 / 括弧は深さ 1 / 平坦な式の演算子は 6 個以内
#         / 32 文字以内 / 結果は 10^8 未満
# ===========================================================================
my $F_GRAMMAR = qr/
  ^(?&E)\z
  (?(DEFINE)
    (?<E>(?&T)(?:\+(?&T))*)
    (?<T>(?&F)(?:[*\/](?&F))*)
    (?<F>\((?&E)\)|[0-9]+)
  )
/x;
my $F_BOUNDS = qr/
  ^(?&T)(?:\+(?&T)){0,6}\z
  (?(DEFINE)
    (?<N>[0-9]{1,4})
    (?<FT>(?&N)(?:[*\/](?&N))?)
    (?<FE>(?&FT)(?:\+(?&FT)){0,6})
    (?<A>(?&N)|\((?&FE)\))
    (?<T>(?&A)(?:[*\/](?&A))?)
  )
/x;
# 乗除 (リテラル同士のペア)。除算は先読み+後方参照 (オペランドが小さいので十分速い)。
my $F_MULDIV = qr/
    (?<![x#])(\#)(?=x*+[*\/]\#)
  | \Gx(?=x*+\*\#(x*+))
  | \G(?=(x)x*+\/\#(x++))\4
  | \Gx(?=x*+\/)
  | (?<=[x#])[*\/]\#x*+
/x;
my $F_MULDIV_ADD = qr/$F_MULDIV|\+\#/;
my $F_PAREN_ADD  = qr/\+\#(?=[x#+]*\))|[()]/;
my $F_DEC;
sub _fixed_dec_re {
    my $src = '^\#';
    for my $q (reverse 0 .. 7) {
        my $b   = 10 ** $q;                                      # const-x
        my @alt = map {
            my $d = $_;
            $d ? "(?:x{$b}){$d}(?=[^\@]*+\@.{$d}(\\d))" : "(?=[^\@]*+\@(\\d))"    # const-x
        } reverse 0 .. 9;
        $src .= '(?|' . join('|', @alt) . ')';
    }
    return qr/$src\@.*\z/;    # const-x
}

sub calc_fixed {
    my ($expr) = @_;
    local $COUNT = 0;
    die "Invalid characters\n" unless defined $expr && $expr =~ /^[0-9\s()+*\/-]+\z/;
    my $s = join '', split /\s+/, $expr;                         # 空白除去は数えない (split)
    die "Subtraction is not supported by calc_fixed\n" if $s =~ /-/;
    die "Invalid expression\n" unless $s =~ $F_GRAMMAR;
    die "Out of fixed-mode bounds\n" unless $s !~ /^.{33}/ && $s =~ $F_BOUNDS;

    tick('append-table', $APPEND, $s, $TBL_B, '');
    $s =~ s/$APPEND/$TBL_B/;
    tock($s);
    tick('to-unary', $RE_B, $s, q{$1$3$5$7$9$9$9$9$9$9$9$9$9$9${10}}, 'g');
    $s =~ s/$RE_B/$1$3$5$7$9$9$9$9$9$9$9$9$9$9${10}/g;
    tock($s);

    die "Division by zero\n" if $s =~ /\/\#(?!x)/;
    tick('mul/div', $F_MULDIV, $s, q{$1$2$3}, 'g');
    $s =~ s/$F_MULDIV/$1$2$3/g;
    tock($s);

    tick('add-in-parens, strip parens', $F_PAREN_ADD, $s, q{}, 'g');
    $s =~ s/$F_PAREN_ADD//g;
    tock($s);

    die "Division by zero\n" if $s =~ /\/\#(?!x)/;
    tick('mul/div+add', $F_MULDIV_ADD, $s, q{$1$2$3}, 'g');
    $s =~ s/$F_MULDIV_ADD/$1$2$3/g;
    tock($s);

    $s =~ /^\#x*\@/ or die "Out of fixed-mode bounds\n";
    $F_DEC //= _fixed_dec_re();
    tick('to-decimal', $F_DEC, $s, q{$1$2$3$4$5$6$7$8}, 'g');
    $s =~ s/$F_DEC/$1$2$3$4$5$6$7$8/g;
    tock($s);
    die "Result too large for fixed mode\n" if $s =~ /x/;
    $s =~ /^0*(\d+)\z/ or die "Out of fixed-mode bounds\n";
    return ($1, $COUNT);
}

1;
