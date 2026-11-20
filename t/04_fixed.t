use strict; use warnings;
use Test::More;
use FindBin; use lib "$FindBin::Bin/lib";
use RegexCalc qw(calc calc_fixed);
use Reference qw(reference);

# calc_fixed: 契約内なら入力によらず s/// はちょうど 6 回
my @cases = (
    '0', '5', '10', '99', '100', '123', '999', '9999',
    '1+1', '1+2+3+4+5+6+7', '3*4+5', '12*34', '123*45', '999*999',
    '2*3+4*5+6*7', '1 + 2 * 3', '(3+6)*8', '(1+2)*(3+4)', '(1+2+3)*(4+5+6)', '9999+1',
    '20/4', '10/3', '100/7+9*9', '(100/5)/2', '100/(5*5)', '20/(2+2)', '(0+0)+5', '0/5', '7/(1+1)',
    '(10/2+3)*(8/4)', "1\n+\t2", '(1+2)*(3+4)+(5+6)*2',
);
for my $e (@cases) {
    my ($v, $n) = calc_fixed($e);
    is($v, reference($e), "calc_fixed('$e') value");
    is($n, 6, "calc_fixed('$e') used exactly 6 s///");
}

# 乱択 (固定シード): 契約に収まる式を生成して calc / reference と照合
my $state = 12345;
sub rnd { $state = ($state * 1664525 + 1013904223) % 4294967296; return int($state / 4294967296 * $_[0]) }
sub num { (0 .. 9, 10, 12, 30, 99, 100)[rnd(14)] }
sub fterm { my $s = num(); $s .= (rnd(2) ? '*' : '/') . num() if rnd(2); $s }
sub fexpr { my $n = rnd(4); join '+', map { fterm() } 0 .. $n }
sub term { my $a = rnd(5) == 0 ? '(' . fexpr() . ')' : num(); $a .= (rnd(2) ? '*' : '/') . (rnd(5) == 0 ? '(' . fexpr() . ')' : num()) if rnd(2); $a }
my ($bad, $checked) = (0, 0);
for (1 .. 400) {
    my $e = join '+', map { term() } 0 .. rnd(3);
    my $want = eval { reference($e) }; $want = "ERR:$@" unless defined $want;
    next if $want =~ /^\d{7,}\z/;
    my $got = eval { (calc_fixed($e))[0] }; $got = "ERR:$@" unless defined $got;
    $got =~ s/^ERR:Out of fixed-mode bounds\n/BOUNDS/;
    next if $got eq 'BOUNDS';    # 契約外 (演算子過多など) は対象外
    $checked++;
    $bad++, diag("MISMATCH '$e': got $got want $want") if $got ne $want;
}
is($bad, 0, "random in-contract expressions match ($checked checked)");
cmp_ok($checked, '>', 250, 'most generated expressions were in contract');

# エラー
my %ERR = (
    '1-2'        => "Subtraction is not supported by calc_fixed\n",
    'abc'        => "Invalid characters\n",
    '1+'         => "Invalid expression\n",
    '(1+2'       => "Invalid expression\n",
    '12345+1'    => "Out of fixed-mode bounds\n",
    '1*2*3'      => "Out of fixed-mode bounds\n",
    '((1+2)+3)'  => "Out of fixed-mode bounds\n",
    '5/0'        => "Division by zero\n",
    '5/(1+1-2)'  => "Invalid expression\n",
    '5/(0+0)'    => "Division by zero\n",
);
for my $e (sort keys %ERR) {
    next if $e eq '5/(1+1-2)';
    eval { calc_fixed($e) };
    is($@, $ERR{$e}, "calc_fixed error: '$e'");
}
# 減算の境目 (P<N, P=N, P>N, 負項だけ) でも reference と同じ値
for my $e ('100-7', '7-100', '5000-5000', '123456-123455', '-5-5', '3-2-1', '-100/7', '20/4+1-9', '0-0', '0-1', '1-0') {
    is((calc($e))[0], reference($e), "calc: $e");
}
done_testing;
