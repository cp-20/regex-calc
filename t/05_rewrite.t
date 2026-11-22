use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use RegexCalc::Rewrite qw(calc_rewrite);
use Reference qw(reference);

# 書き換え系モード: 1 本の正規表現を変化がなくなるまで s///g するだけ。値は calc と同じ規則 (0 方向への切り捨て)。
sub run { my $e = shift; local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm 30; my $r = eval { (calc_rewrite($e))[0] }; alarm 0; defined $r ? $r : "ERR:$@" }

# --- 本体の Perl は「表の付加・書き換えループ」の 2 つの s/// だけ ---
{
    open my $fh, '<', "$FindBin::Bin/../lib/RegexCalc/Rewrite.pm" or die $!;
    my $src = do { local $/; <$fh> };
    $src =~ s/^\s*#.*$//mg;              # コメント行
    $src =~ s/(?<=\s)#(?:\s.*)?$//mg;    # 行末コメント (' # ...')
    my @subst = $src =~ m{(?<![\w\$\@%>\\])s/(?:\\.|[^/\\\n])*/(?:\\.|[^/\\\n])*/[a-z]*}g;
    is(scalar(@subst), 2, 'Rewrite.pm has exactly 2 s/// (append table, the rewrite loop)');
    my @loops = $src =~ /\b(for|foreach|while|until)\b/g;
    is_deeply(\@loops, ['until'], 'the only loop is the rewrite loop');
}

my @SEM = (
    ['0', '0'], ['5', '5'], ['10', '10'], ['99', '99'], ['100', '100'], ['9999', '9999'], ['123456', '123456'], ['1234567', '1234567'],
    ['1+1', '2'], ['1+2+3+4+5+6+7+8+9', '45'], ['3*4+5', '17'], ['12*34', '408'], ['999*999', '998001'],
    ['1*2*3*4*5', '120'], ['1-2+3-4+5', '3'], ['1-2-3-4', '-8'], ['-1-2-3', '-6'], ['100-2*60+5', '-15'],
    ['8/2/2', '2'], ['1/3', '0'], ['(3+6)*8', '72'], ['(1+2)*(3+4)', '21'], ['(((1+2)))', '3'],
    ['1 + 2 * 3', '7'], ['2 3', '23'], ["1\n+\t2", '3'], ['100000+1', '100001'], ['100000/2', '50000'],
    ['-0', '0'], ['--5', '5'], ['-(-5)', '5'], ['-(-(-5))', '-5'], ['2--3', '5'], ['2+-3', '-1'],
    ['2*-3', '-6'], ['-2*-3', '6'], ['-2*3*-4', '24'], ['2-(-3)', '5'], ['3---3', '0'], ['2---3', '-1'],
    ['6/2*3', '9'], ['2*3/4', '1'], ['9/2*2', '8'], ['100/10/2', '5'],
    ['7/2', '3'], ['-7/2', '-3'], ['7/-2', '-3'], ['-7/-2', '3'], ['-1/2', '0'], ['-6/4', '-1'],
    ['007+0', '7'], ['000', '0'], ['8-10*-33', '338'], ['2-2*-2', '6'], ['2-2/-2', '3'], ['-10-7*-71', '487'],
    ['(--5)', '5'], ['-(--5)', '-5'], ['2-(--5)', '-3'], ['2*(--5)', '10'], ['(--5)*3', '15'], ['((--5))', '5'],
    ['00000000012', '12'], ['123456*0', '0'], ['0*123456', '0'], ['100-100', '0'], ['99999-100000', '-1'],
    ['1000000-1', '999999'], ['12345678+1', '12345679'],
    ['2*3*4*5*6*7', '5040'], ['1-1*1-1*1', '-1'], ['-1*-1*-1*-1', '1'], ['100/7+9/2', '18'], ['-100/7', '-14'],
    [join('+', 1 .. 100), '5050'], [join('-', 500, (1) x 20), '480'],
);
is(run($_->[0]), $_->[1], "calc_rewrite('$_->[0]')") for @SEM;

# パス数の上限 (calc と同じかそれ以下)。[式, 上限]
for my $c (['5', 3], ['123456', 4], ['12345678', 4], ['1+1', 4], ['1+2+3+4+5+6+7+8+9', 4], [join('+', 1 .. 100), 4],
           ['3*4+5', 5], ['999*999', 4], ['1*2*3*4*5', 6], ['(((1+2)))', 5], ['((((((((1))))))))', 5], ['1-2-3-4', 5], ['100-2*60+5', 6], ['8/2/2', 5],
           ['(3+6)*8', 5], ['(1+2)*(3+4)', 5], ['8-10*-33', 5], ['1 + 2 * 3', 5], ['100000/2', 5], ['1000000/3', 5]) {
    my ($e, $budget) = @$c;
    my (undef, $n) = calc_rewrite($e);
    ok($n <= $budget, "'$e' used $n s/// (budget $budget)");
}
for my $e ('99/1', '100/1', '101/1', '9999/1', '10000/1', '10001/1', '20000/2', '1000000/1', '1000000/3', '99999/99999', '99999/100000') {
    is(run($e), reference($e), "divide: $e");
}

# エラー
for my $e ('', 'abc', '1.5', '1e3', '1%2', '1,2', '"1"', '1 2a') { is(run($e), "ERR:Invalid characters\n", "chars: '$e'") }
for my $e ('   ', '()', '(1+', '1+', '+3', '*3', '3*', '3**4', '2(3)', '(1)(2)', '1+2)', '()3', '--', '-', '1//2', '((1)', '1 2 +') {
    is(run($e), "ERR:Invalid expression\n", "syntax: '$e'");
}
for my $e ('1/0', '0/0', '-1/0', '5/(2-2)', '1/(1-1)', '0/(0-0)', '5/-0', '(2*3+(4/(1-1)))*999') {
    is(run($e), "ERR:Division by zero\n", "div0: '$e'");
}
is(run('123456789'), "ERR:Number too large\n", 'too many digits');

# 乱択 (固定シード) で reference と照合
my $state = 0xbeef;
sub rnd { $state = ($state * 1664525 + 1013904223) % 4294967296; return int($state / 4294967296 * $_[0]) }
my @values = (0 .. 12, 20, 30);
sub atom { my $d = shift; return '(' . expression($d - 1) . ')' if $d > 0 && rnd(10) < 2;
           my $v = $values[rnd(scalar @values)]; return rnd(5) == 0 ? "-$v" : $v }
sub factor { my $d = shift; my $s = rnd(4) == 0 ? (rnd(2) ? '--' : '-') : ''; return $s . atom($d) }
sub term { my $d = shift; my $s = factor($d); $s .= (rnd(2) ? '*' : '/') . factor($d) for 1 .. rnd(3); $s }
sub expression { my $d = shift; my $s = term($d); $s .= (rnd(2) ? '+' : '-') . term($d) for 1 .. rnd(3); $s }

my ($bad, $n) = (0, 0);
my @exprs = map { expression(2) } 1 .. 300;
push @exprs, rnd(100000) . ('+', '-')[rnd(2)] . rnd(100000) . ('+', '-', '/')[rnd(3)] . (1 + rnd(300)) for 1 .. 100;
push @exprs, (1 + rnd(3000)) . ('*', '/', '+')[rnd(3)] . (1 + rnd(300)) . ('+', '-')[rnd(2)] . rnd(5000) for 1 .. 100;
for my $e (@exprs) {
    my $want = eval { reference($e) } // "ERR:$@";
    next if $want =~ /^-?\d{7,}\z/;    # 単項表現が巨大になる式は除外
    my $got = run($e);
    $n++;
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}
is($bad, 0, "$n random expressions match the reference");

# a op b op c の符号全組み合わせ (3,456 通り)
$bad = 0;
for my $v1 (2, 3, 5) { for my $s1 ('', '-') { for my $o1 ('+', '-', '*', '/') {
for my $v2 (2, 3, 5) { for my $s2 ('', '-') { for my $o2 ('+', '-', '*', '/') {
for my $v3 (2, 3, 5) { for my $s3 ('', '-') {
    my $e = "$s1$v1$o1$s2$v2$o2$s3$v3";
    my ($got, $want) = (run($e), reference($e));
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}}}}}}}}
is($bad, 0, 'all sign combinations match the reference');
done_testing;
