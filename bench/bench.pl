#!/usr/bin/env perl
# Measure s/// pass counts and wall time per calc() call.
#   perl bench/bench.pl            # built-in expressions, plain table
#   perl bench/bench.pl --md       # Markdown table (used in README)
#   perl bench/bench.pl '2*3+4'    # your own expressions
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Time::HiRes qw(time);
use RegexCalc qw(calc calc_fixed);
use RegexCalc::Rewrite qw(calc_rewrite);

my $md = 0;
my @exprs;
for (@ARGV) { if ($_ eq '--md') { $md = 1 } else { push @exprs, $_ } }
@exprs = (
    '(3+6)*8', '100-2*60+5', '1+2+3+4+5+6+7+8+9', '1-2-3-4-5-6-7-8-9', '(1+2)*(3+4)',
    '((1+2)*3+4)*2', '8-10*-33', '999*999', '123456', '100000+1', '100000/2',
) unless @exprs;

# Run calc repeatedly for at least 0.3 s (or 20000 times) and return us/call.
sub per_call {
    my ($f, $e) = @_;
    $f->($e) for 1 .. 3;    # warm up (compiles the lazily built patterns)
    my ($t0, $n) = (time, 0);
    do { $f->($e); $n++ } while (time - $t0 < 0.3 && $n < 20000);
    return (time - $t0) * 1e6 / $n;
}

sub fmt_us { my $u = shift; $u < 10 ? sprintf('%.2f', $u) : $u < 1000 ? sprintf('%.1f', $u) : sprintf('%.0f', $u) }

my @rows;
for my $e (@exprs) {
    my ($v, $n) = eval { calc($e) };
    if ($@) { (my $err = $@) =~ s/\s+\z//; push @rows, [$e, "error: $err", '-', '-', '-', '-']; next }
    my (undef, $rn) = calc_rewrite($e);
    push @rows, [$e, $v, $n, fmt_us(per_call(\&calc, $e)), $rn, fmt_us(per_call(\&calc_rewrite, $e))];
}

printf "perl %vd, %s\n\n", $^V, $^O;
if ($md) {
    print "| 式 | 結果 | `s///` の回数 | 1回あたり (µs) | 書き換え系: 回数 | 書き換え系: µs |\n| --- | ---: | ---: | ---: | ---: | ---: |\n";
    printf "| `%s` | %s | %s | %s | %s | %s |\n", @$_ for @rows;
} else {
    printf "%-20s %10s %7s %12s %9s %12s\n", 'expr', 'result', 'passes', 'us/call', 'rewrite', 'us/call';
    printf "%-20s %10s %7s %12s %9s %12s\n", @$_ for @rows;
}
