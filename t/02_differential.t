use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use RegexCalc qw(calc);
use Reference qw(reference);

sub run { my ($f, $e) = @_; local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm 30; my $r = eval { ($f->($e))[0] }; alarm 0; defined $r ? $r : "ERR:$@" }

# 固定シードの線形合同法 (再現可能)
my $state = 0xc0ffee;
sub rnd { $state = ($state * 1664525 + 1013904223) % 4294967296; return int($state / 4294967296 * $_[0]) }

my @values = (0 .. 12, 20, 30);
sub atom { my $d = shift; return '(' . expression($d - 1) . ')' if $d > 0 && rnd(10) < 2;
           my $v = $values[rnd(scalar @values)]; return rnd(5) == 0 ? "-$v" : $v }
sub factor { my $d = shift; my $s = rnd(4) == 0 ? (rnd(2) ? '--' : '-') : ''; return $s . atom($d) }
sub term { my $d = shift; my $s = factor($d); $s .= (rnd(2) ? '*' : '/') . factor($d) for 1 .. rnd(3); $s }
sub expression { my $d = shift; my $s = term($d); $s .= (rnd(2) ? '+' : '-') . term($d) for 1 .. rnd(3); $s }

my ($bad, $skipped) = (0, 0);
for my $i (1 .. 300) {
    my $e = expression(2);
    $e =~ s/(\d+)/rnd(8) == 0 ? " $1 " : $1/ge if $i % 7 == 0;    # テスト側なので /e もよい: 空白混入
    my $want = run(\&reference, $e);
    if ($want =~ /^-?\d{6,}\z/) { $skipped++; next }    # 単項表現が巨大になる式は除外 (結果が 10^5 超)
    my $got = run(\&calc, $e);
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}
diag("skipped $skipped huge-valued expressions");
is($bad, 0, '300 random expressions match the reference');

# a op b op c の符号全組み合わせ (3,456 通り)
my $n = 0; $bad = 0;
for my $v1 (2, 3, 5) { for my $s1 ('', '-') { for my $o1 ('+', '-', '*', '/') {
for my $v2 (2, 3, 5) { for my $s2 ('', '-') { for my $o2 ('+', '-', '*', '/') {
for my $v3 (2, 3, 5) { for my $s3 ('', '-') {
    my $e = "$s1$v1$o1$s2$v2$o2$s3$v3";
    $n++;
    my ($got, $want) = (run(\&calc, $e), run(\&reference, $e));
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}}}}}}}}
is($n, 3456, 'sign combinations enumerated');
is($bad, 0, 'all sign combinations match the reference');

# 大きめの値 (桁またぎ・5-6 桁)。乗算は単項が巨大になるので小さい値だけ。
$bad = 0;
for my $i (1 .. 200) {
    my $e = rnd(100000) . ('+', '-')[rnd(2)] . rnd(100000) . ('+', '-', '/')[rnd(3)] . (1 + rnd(300));
    $e = '(' . $e . ')*' . (1 + rnd(9)) if $i % 5 == 0;
    my ($got, $want) = (run(\&calc, $e), run(\&reference, $e));
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}
for my $i (1 .. 100) {
    my $e = (1 + rnd(3000)) . ('*', '/', '+')[rnd(3)] . (1 + rnd(300)) . ('+', '-')[rnd(2)] . rnd(5000);
    my ($got, $want) = (run(\&calc, $e), run(\&reference, $e));
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}
is($bad, 0, 'multi-digit expressions match the reference');
done_testing;
