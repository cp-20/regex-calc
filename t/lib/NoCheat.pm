package NoCheat;
# 「ズルをしていない」ことの機械的な検査。電卓本体 (lib/**/*.pm) のソースを走査して、
# 値の計算を s/// 以外に逃がす構文を検出する。ヒューリスティックだが、違反の典型形は漏れなく拾う。
use strict; use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(lint);

# 返り値: 違反メッセージのリスト (空なら OK)
sub lint {
    my ($src, $name) = @_;
    $name //= 'source';
    my @bad;
    my @lines = split /\n/, $src;
    my (@code, $pod);
    for my $i (0 .. $#lines) {
        my $l = $lines[$i];
        if ($l =~ /^=(?!cut)\w/) { $pod = 1 }
        if ($pod) { $pod = 0 if $l =~ /^=cut/; push @code, ''; next }
        last if $l =~ /^__(?:END|DATA)__/;
        my $marked = $l =~ /const-x/;                     # 定数だけから作る x / ** の自己申告
        $l =~ s/(?<=\s)#(?:\s.*)?$//;                     # 行末コメント (' # ...')
        $l = '' if $l =~ /^\s*#/;
        push @code, [$l, $marked];
    }
    my $text = join "\n", map { ref $_ ? $_->[0] : '' } @code;

    # --- s/// の検査: 区切りは / だけ許可し、フラグに e を許さない ---
    my $n_subst = 0;
    while ($text =~ m{(?<![\w\$\@%>\\])s/((?:\\.|[^/\\\n])*)/((?:\\.|[^/\\\n])*)/([a-z]*)}g) {
        $n_subst++;
        my $flags = $3;
        push @bad, "$name: s///$flags uses the /e flag (replacement code)" if $flags =~ /e/;
    }
    push @bad, "$name: s with a non-'/' delimiter (the lint can't inspect it)"
        if $text =~ /(?<![\w\$\@%>:\\])s\s*[{(\[!|#,]/;

    my $n_tick = 0;
    for my $i (0 .. $#code) {
        next unless ref $code[$i];
        my ($l, $marked) = @{ $code[$i] };
        $n_tick++ while $l =~ /\btick\(/g and $l !~ /^\s*sub tick\b/;
        my $has_subst = $l =~ m{(?<![\w\$\@%>\\])s/(?:\\.|[^/\\])*/(?:\\.|[^/\\])*/[a-z]*};
        if ($has_subst) {
            my $prev = $i ? (ref $code[$i-1] ? $code[$i-1][0] : '') : '';
            push @bad, "$name:" . ($i+1) . ": s/// without tick() (every pass must be counted)"
                unless $l =~ /\btick\(.*s\// || $prev =~ /\btick\(/;
        }
        push @bad, "$name:" . ($i+1) . ": x-repeat with a variable count needs a '# const-x' marker"
            if $l =~ /\sx\s+[\$(]/ && !$marked;
        push @bad, "$name:" . ($i+1) . ": ** needs a '# const-x' marker"
            if $l =~ /\*\*/ && !$marked && $l !~ /s\/|qr\//;
    }
    push @bad, "$name: number of s/// ($n_subst) != number of tick() calls ($n_tick)" if $n_subst != $n_tick;
    push @bad, _lint_patterns($text, [map { ref $_ ? $_->[1] : 0 } @code], $name);

    # --- 作業文字列 (式・値) に定数テキストを連結しない: 表・予備・符号は s/// で足す (数える) ---
    #   許す連結は「計算した部分結果を元の場所へ戻す」構造操作だけ (括弧の中身・式の部分と運んでいる表)。
    my $W = '(?:s|e|u|w|out|pair|expr|body)';          # 作業文字列を持つ変数名
    my @allow = (
        qr/^\s*\$s\s*=\s*\$pre\s*\.\s*_flat\(\$in\)\s*\.\s*\$post;\s*$/,          # 括弧の結果を戻す
        qr/^\s*\$s\s*=\s*\$pre\s*\.\s*\$out\s*\.\s*\$post;\s*$/,                  # 乗除のペアの結果を戻す
        qr/^\s*\$s\s*=\s*_flat\(\$body\)\s*\.\s*\$table;\s*$/,                      # 式の部分の結果 + 運んでいる表
    );
    for my $i (0 .. $#code) {
        next unless ref $code[$i];
        my $l = $code[$i][0];
        next if grep { $l =~ $_ } @allow;
        (my $c = $l) =~ s/\bs\/(?:\\.|[^\/\\])*\/(?:\\.|[^\/\\])*\/[a-z]*//g;        # s/// の中身は見ない
        $c =~ s/\b(?:qr|m)\/(?:\\.|[^\/\\])*\/[a-z]*//g;
        $c =~ s/=~\s*\/(?:\\.|[^\/\\])*\/[a-z]*//g;
        push @bad, "$name:" . ($i+1) . ": '.=' on a working string (append text with a counted s///)"
            if $c =~ /\$$W\s*\.=/;
        push @bad, "$name:" . ($i+1) . ": concatenation onto a working string (append text with a counted s///)"
            if $c =~ /(?<![\w\$])\$$W\s*\.(?!=)|(?<![.])\.\s*\$$W\b/;
        push @bad, "$name:" . ($i+1) . ": text concatenated into a working string"
            if $c =~ /(?<![\w\$])\$$W\s*=(?![=~])[^;]*(?:\.\s*['"]|['"]\s*\.)/;
        push @bad, "$name:" . ($i+1) . ": working string interpolated into a larger string"
            if $c =~ /"(?=[^"]*\$$W\b)(?!\$$W")[^"]*"/;
    }

    my %forbidden = (
        '(?{ code })'    => qr/\(\?\??\{|\(\*\{|\(\?\(\?\{/,
        'tr/// or y///'  => qr/(?<![\w\$\@%>:\\])(?:tr|y)\s*[\/{(\[!|#,]/,
        'eval'           => qr/\beval\b/,
        'Math::Big*'     => qr/Math::Big|bigint|bignum/,
        'length()'       => qr/\blength\b/,
        'sprintf/printf' => qr/\bs?printf\b/,
        'pos()'          => qr/\bpos\b/,
        'substr/vec'     => qr/\b(?:substr|vec)\b/,
        'numeric builtin'=> qr/\b(?:ord|chr|hex|oct|int|abs|sqrt|pack|unpack|index|rindex)\b/,
        'numeric compare'=> qr/\s(?:==|!=|<=>|<=|>=)\s/,
        'numeric op-assign' => qr/(?<![.|\/&])[-+*\/%]=(?![=~])/,
        'increment (other than $COUNT++)' => qr/\$(?!COUNT\b)\w+\s*(?:\+\+|--)|(?:\+\+|--)\s*\$\w+/,
        '$#array / scalar(@x)' => qr/\$#|\bscalar\s*\(?\s*@/,
        'use of other modules' => qr/^\s*use\s+(?!strict|warnings|Exporter|5\.|v5)/m,
        'string eval-ish (do/require/ee)' => qr/\b(?:require|do\s+\{?\s*\$)/,
    );
    for my $what (sort keys %forbidden) {
        my $re = $forbidden{$what};
        for my $i (0 .. $#code) {
            next unless ref $code[$i];
            push @bad, "$name:" . ($i+1) . ": forbidden: $what" if $code[$i][0] =~ $re;
        }
    }
    return @bad;
}

# ---------------------------------------------------------------------------
# 「パターンと置換文字列は定数だけから作る」の検査 (値由来の数・部分文字列を埋め込むズルの防止)
#
#   R1 正規表現リテラル (qr// m// s/// =~ // split // m{} qr{}) に展開してよい変数は、ファイル先頭で宣言した
#      定数 (大文字だけの名前: $FAST, $RE_B ...) だけ。$1 などのキャプチャ変数・小文字の変数・配列・@{[ ]} は不可。
#      例外: 'const-x' の印が付いた行 (ビルダー関数の中) と、`my $re = _dec($k)` で得たプラン ($re)。
#   R2 s/// の置換部に書いてよい変数は $1..$99 (${10} も) と大文字の定数だけ。
#   R3 `{$x}` のように量化子の数を変数で書いた行と、'const-x' の印は、ファイル直下かビルダー関数
#      (_table _unary_re _dec_re _fixed_dec_re _dec) の中でしか使えない。ビルダーの呼び出しは、ファイル直下で
#      数字の引数だけ、または形状テストで選んだ $k を渡す _dec($k) だけ。
#   R4 =~ $var / !~ $var の右辺も R1 と同じ名前規則。
# ---------------------------------------------------------------------------
my %BUILDER = map { $_ => 1 } qw(_table _unary_re _dec_re _fixed_dec_re _dec);

sub _line_of { my ($text, $off) = @_; my $pre = substr($text, 0, $off); return 1 + ($pre =~ tr/\n//) }

sub _lint_patterns {
    my ($text, $marked, $name) = @_;
    my @bad;
    my @lines = split /\n/, $text, -1;

    # 各行がどのサブルーチンの中か (ファイル直下なら '')
    my (@sub_of, $cur);
    $cur = '';
    for my $i (0 .. $#lines) {
        $cur = $1 if $lines[$i] =~ /^sub\s+(\w+)/;
        $sub_of[$i] = $cur;
        $cur = '' if $lines[$i] =~ /^\}/ || ($lines[$i] =~ /^sub\s+\w+.*\}\s*$/);
    }
    my $in_builder = sub { my $i = shift; $sub_of[$i] eq '' || $BUILDER{ $sub_of[$i] } };

    # --- R3: 印と変数量化子は、ファイル直下かビルダー関数の中だけ ---
    for my $i (0 .. $#lines) {
        next unless $marked->[$i] || $lines[$i] =~ /\{\$\w+\}|\{\$\w+,/;
        next if $in_builder->($i);
        push @bad, "$name:" . ($i + 1) . ": 'const-x' / variable quantifier outside the builder subs (sub $sub_of[$i])";
    }
    for my $i (0 .. $#lines) {
        next if $lines[$i] =~ /^\s*sub\s/ && $lines[$i] !~ /_(?:table|unary_re|dec_re|dec)\(/;
        while ($lines[$i] =~ /\b(_table|_unary_re|_dec_re|_fixed_dec_re|_dec)\(([^)]*)\)/g) {
            my ($fn, $args) = ($1, $2);
            next if $lines[$i] =~ /^\s*sub\s+\Q$fn\E\b/;
            next if $BUILDER{ $sub_of[$i] } && $sub_of[$i] ne '_dec' && $sub_of[$i] ne '';   # ビルダー同士の呼び出し
            if ($sub_of[$i] eq '' ) {
                push @bad, "$name:" . ($i + 1) . ": $fn(...) at file scope must take numeric literals only"
                    unless $args =~ /^[\d\s,]*\z/;
            }
            elsif ($sub_of[$i] eq '_dec' && $fn eq '_dec_re') {
                push @bad, "$name:" . ($i + 1) . ": _dec_re must be called with the table index only"
                    unless $args =~ /^\$_\[0\]\z/;
            }
            else {
                # 実行時の呼び出しは、同じサブルーチン内で形状テストから選んだ $k を渡す _dec($k) だけ
                my $ok = $fn eq '_dec' && $args =~ /^\$k\z/ && _sub_has($text, \@lines, \@sub_of, $i, qr/\$k\s*=\s*\$\w+\s*=~\s*\/\^(?:-\?\\#\?)?(?:\(\?:x\{\d+\}\)\{\d+\}|x\{\d+\})\//);
                $ok ||= $fn eq '_fixed_dec_re' && $args eq '';
                push @bad, "$name:" . ($i + 1) . ": runtime call $fn($args) may only pass a \$k chosen by /^x{N}/ shape tests"
                    unless $ok;
            }
        }
    }

    # --- R1 / R2 / R4: 正規表現リテラルを取り出して展開を検査 ---
    my @lit;    # [offset, body, kind]
    while ($text =~ m'\b(?:qr|m)\s*/((?:\\.|[^/\\])*)/'gs)                { push @lit, [$-[1], $1, 'pat'] }
    while ($text =~ m'\b(?:qr|m)\s*\{((?:\\.|[^}\\])*)\}'gs)              { push @lit, [$-[1], $1, 'pat'] }
    while ($text =~ m'(?:=~|!~|\bsplit)\s*/((?:\\.|[^/\\])*)/'gs)         { push @lit, [$-[1], $1, 'pat'] }
    while ($text =~ m'(?<![\w\$\@%>:\\])s/((?:\\.|[^/\\\n])*)/((?:\\.|[^/\\\n])*)/[a-z]*'g) {
        push @lit, [$-[1], $1, 'pat'], [$-[2], $2, 'repl'];
    }
    for my $l (@lit) {
        my ($off, $body, $kind) = @$l;
        (my $b = $body) =~ s/\\./ZZ/gs;                   # エスケープ済みの文字は展開されない (長さは保つ)
        my @found;
        if ($kind eq 'pat') {
            while ($b =~ /(\$(?:\d+|\w+|\{[^}]*\})|\@(?:\w+|\{))/g) { push @found, [$-[1], $1] }
        }
        else {
            while ($b =~ /(\$(?:\d+|\w+|\{[^}]*\})|\@(?:\w+|\{))/g) { push @found, [$-[1], $1] }
        }
        for my $f (@found) {
            my ($rel, $tok) = @$f;
            my $line = _line_of($text, $off + $rel);
            my $i    = $line - 1;
            (my $v = $tok) =~ s/^\$\{?|\}$//g;
            if ($kind eq 'repl') {
                next if $v =~ /^[1-9]\d?\z/ || $v =~ /^[A-Z][A-Z0-9_]*\z/;
                push @bad, "$name:$line: replacement interpolates '$tok' (only capture groups \$1..\$99 and CONSTANTS are allowed)";
                next;
            }
            next if $tok =~ /^\$/ && $v =~ /^[A-Z][A-Z0-9_]*\z/;
            next if $marked->[$i] && $in_builder->($i);
            next if $tok eq '$re' && _re_is_plan($text);
            push @bad, "$name:$line: pattern interpolates '$tok' (only file-scope CONSTANTS or builder-sub lines marked const-x)";
        }
    }
    # R4: =~ $var
    while ($text =~ /(?:=~|!~)\s*\$(\w+)/g) {
        my ($v, $off) = ($1, $-[1]);
        next if $v =~ /^[A-Z][A-Z0-9_]*\z/;
        next if $v eq 're' && _re_is_plan($text);
        push @bad, "$name:" . _line_of($text, $off) . ": pattern taken from the variable '\$$v' (only CONSTANTS)";
    }
    return @bad;
}

# $re に代入してよいのは `_dec($k)` の結果だけ
sub _re_is_plan {
    my ($text) = @_;
    while ($text =~ /\$re\s*=(?![=~])\s*([^;]*);/g) { return 0 unless $1 =~ /^_dec\(\$k\)\z/ }
    return 1;
}

sub _sub_has {
    my ($text, $lines, $sub_of, $i, $re) = @_;
    for my $j (0 .. $#$lines) { return 1 if $sub_of->[$j] eq $sub_of->[$i] && $lines->[$j] =~ $re }
    return 0;
}
1;
