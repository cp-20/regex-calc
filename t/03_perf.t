use strict; use warnings;
use Test::More;
use Time::HiRes qw(time);
use RegexCalc qw(calc);

# パターンは入力から作らない (後方参照だけ) ので、速さは設計で決まる。
# 絶対値の上限は遅いマシンでも落ちない緩さにし、本命は「入力 4 倍で時間が何倍になるか」(二次なら 16 倍)。
sub t { my $e = shift; calc($e); my $t0 = time; my ($v) = calc($e); return (time - $t0, $v) }    # 2 回目を測る (遅延生成するパターンのコンパイルを除く)
sub best { my $e = shift; my @t = map { (t($e))[0] } 1 .. 3; (sort { $a <=> $b } @t)[0] }

for my $c (['100000+1', '100001'], ['100000/2', '50000'], ['200000-1', '199999'], ['100000-99999', '1'], ['100000-100000', '0']) {
    my ($e, $want) = @$c;
    my ($t, $v) = t($e);
    is($v, $want, $e);
    cmp_ok($t, '<', 2, sprintf('%s took %.1f ms (< 2 s)', $e, $t * 1000));
}

# 傾き: 入力が 4 倍 (25000 -> 100000) のとき。線形なら約 4 倍、二次なら約 16 倍。
# 除算・減算は理論上は線形だが、ブロックごとの走査やアロケータの都合で 4 倍ちょうどにはならないので、10 倍未満で判定する。
for my $f ('%d+1', '%d-1', '%d-24999', '%d/2', '%d/7') {
    my ($t1, $t2) = (best(sprintf $f, 25000), best(sprintf $f, 100000));
    cmp_ok($t2 / ($t1 || 1e-6), '<', 10, sprintf("%s: %.2f ms -> %.2f ms for 4x input (ratio %.1f, quadratic would be ~16)", $f, $t1 * 1000, $t2 * 1000, $t2 / ($t1 || 1e-6)));
}
done_testing;
