use strict; use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use NoCheat qw(lint);
use File::Find;

# --- 電卓本体を走査 ---
my @files;
find({ wanted => sub { push @files, $File::Find::name if /\.pm\z/ }, no_chdir => 1 }, "$FindBin::Bin/../lib");
ok(scalar(@files) >= 1, 'found lib/**/*.pm');
for my $f (sort @files) {
    open my $fh, '<:encoding(UTF-8)', $f or die "$f: $!";
    my $src = do { local $/; <$fh> };
    my @bad = lint($src, $f);
    is_deeply(\@bad, [], "no forbidden constructs in $f") or diag join "\n", @bad;
}

# --- 検査器自身のテスト: 典型的なズルを確実に拾えること ---
my %CHEAT = (
    '/e flag'          => q{tick('a'); $s =~ s/(\d+)/$1+1/ge;},
    '/ee flag'         => q{tick('a'); $s =~ s/(\d+)/$1+1/gee;},
    '(?{ })'           => q{my $re = qr/a(?{ $x++ })/;},
    '(??{ })'          => q{my $re = qr/a(??{ $x })/;},
    'tr'               => q{(my $t = $s) =~ tr/x//;},
    'y'                => q{$s =~ y/a-z/A-Z/;},
    'eval'             => q{my $v = eval "1+2";},
    'length'           => q{my $n = length($s);},
    'sprintf'          => q{my $t = sprintf("%d", 3);},
    'Math::BigInt'     => q{use Math::BigInt;},
    'pos'              => q{my $p = pos($s);},
    'substr'           => q{my $t = substr($s, 0, 1);},
    'numeric compare'  => q{my $z = $a == $b;},
    'increment'        => q{$i++;},
    'x with variable'  => q{my $r = 'x' x $n;},
    'untracked s///'   => q{$s =~ s/a/b/g;},
    'other delimiter'  => q{tick('a'); $s =~ s{a}{b}g;},
    # --- パターン・置換文字列に値を持ち込むズル ---
    'qr interpolates a local'      => q{my $re = qr/a$n/;},
    's/// pattern is a local'      => q{tick('a'); $s =~ s/$n/x/g;},
    'match interpolates a local'   => q{my $ok = $s =~ /^x{$n}/;},
    'replacement interpolates'     => q{tick('a'); $s =~ s/a/$n/g;},
    'replacement interpolates {}'  => q{tick('a'); $s =~ s/a/${n}x/g;},
    'array interpolation'          => q{my $re = qr/@{[ $n ]}/;},
    'capture var in a pattern'     => q{my $re = qr/x$1/;},
    '=~ $local'                    => q{my $ok = $s =~ $re2;},
    '!~ $local'                    => q{my $ok = $s !~ $pat;},
    'const-x marker in a runtime sub' => qq{sub run {\n    my \$re = qr/\$q/;    # const-x\n}\n},
    'variable quantifier in a runtime sub' => qq{sub run {\n    my \$p = "x{\$n}";\n}\n},
    'builder called with a variable (file scope)' => q{my $R = _dec_re($n);},
    'builder called at runtime'    => qq{sub run {\n    my \$r = _dec_re(\$len);\n}\n},
    '_dec($k) without a shape test'=> qq{sub run {\n    my \$k = \$n;\n    my \$r = _dec(\$k);\n}\n},
    '$re from something else'      => q{my $re = qr/x/; $re = $foo; $s =~ $re;},
    # --- 作業文字列への定数連結 (表・予備・符号は s/// で足す) ---
    'table appended with .'        => q{my $t = $s . $TBL_B;},
    'table appended with .='       => q{$s .= $TBL_B;},
    'table prepended'              => q{$s = $TBL_B . $s;},
    'marker appended with .='      => q{$e .= '@+';},
    'sign prefixed'                => q{return $neg ? "-$out" : $out;},
    'interpolated into a table'    => q{my $x = "$s$TABLE";},
    'result suffixed'              => q{$out = $out . '#';},
    'copies built by hand'         => q{my $w = "#+$s-|+$s";},
    'splice that adds text'        => q{$s = $pre . '#' . $post;},
);
for my $name (sort keys %CHEAT) {
    my @bad = lint($CHEAT{$name}, 'snippet');
    ok(scalar(@bad), "lint catches: $name") or diag $CHEAT{$name};
}
# 許される書き方は通ること (計算した部分結果を元の場所へ戻す構造操作だけは許す)
my @splice = lint(join("\n",
    q{$s = $pre . _flat($in) . $post;},
    q{$s = $pre . $out . $post;},
    q{$s = _flat($body) . $table;},
    q{return $2 eq '0' ? '0' : "$1$2";},
), 'snippet');
is_deeply(\@splice, [], 'lint accepts the structural splices') or diag join "\n", @splice;
my @ok = lint(q{tick('a'); $s =~ s/x+/$1/g; my $t = 'x' x $q; # const-x} . "\n" . q{$COUNT++;}, 'snippet');
is_deeply(\@ok, [], 'lint accepts the allowed idioms') or diag join "\n", @ok;
my @ok2 = lint(join("\n",
    q{my $A = qr/x+/; my $B = qr/$A|\+/;},
    q{tick('a'); $s =~ s/$B(x)/$1$2${3}$B/g;},
    q{$s =~ $B; $s !~ $B;},
    q{sub _dec_re { my ($k) = @_; my $src = "x{$k}";    # const-x},
    q{    return qr/$src/;    # const-x},
    q{}},
    q{my $R = _dec_re(3);},
    q{sub _dec { $DEC[$_[0]] //= _dec_re($_[0]) }},
    q{sub run { my $k = $s =~ /^x{100}/ ? 3 : 1;},
    q{    my $re = _dec($k);},
    q{    tick('b'); $s =~ s/$re/$1/g; }},
), 'snippet');
is_deeply(\@ok2, [], 'lint accepts constants, builders and shape-tested plans') or diag join "\n", @ok2;
done_testing;
