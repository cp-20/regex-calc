package Reference;
# テスト専用の独立した参照実装 (再帰下降 + Math::BigInt)。電卓本体とは無関係に通常の算術を使う。
use strict; use warnings;
use Math::BigInt;
use Exporter 'import';
our @EXPORT_OK = qw(reference);

sub reference {
    my ($expr) = @_;
    die "Invalid characters\n" unless $expr =~ /^[0-9\s()+*\/-]+\z/;
    (my $src = $expr) =~ s/\s+//g;
    my $i = 0;
    my $peek = sub { substr($src, $i, 1) };
    my ($expression, $term, $unary, $primary);
    $primary = sub {
        if ($peek->() eq '(') {
            $i++;
            my $v = $expression->();
            die "Invalid expression\n" unless $peek->() eq ')';
            $i++;
            return $v;
        }
        die "Invalid expression\n" unless $peek->() =~ /^[0-9]\z/;
        my $d = '';
        $d .= substr($src, $i++, 1) while $i < length($src) && substr($src, $i, 1) =~ /[0-9]/;
        return Math::BigInt->new($d);
    };
    $unary = sub {
        if ($peek->() eq '-') { $i++; return $unary->()->bneg }
        return $primary->();
    };
    $term = sub {
        my $v = $unary->();
        while ($peek->() eq '*' || $peek->() eq '/') {
            my $op = substr($src, $i++, 1);
            my $r  = $unary->();
            if ($op eq '*') { $v = $v->copy->bmul($r) }
            else {
                die "Division by zero\n" if $r->is_zero;
                $v = $v->copy->btdiv($r);    # 0 方向への切り捨て
            }
        }
        return $v;
    };
    $expression = sub {
        my $v = $term->();
        while ($peek->() eq '+' || $peek->() eq '-') {
            my $op = substr($src, $i++, 1);
            my $r  = $term->();
            $v = $op eq '+' ? $v->copy->badd($r) : $v->copy->bsub($r);
        }
        return $v;
    };
    my $v = $expression->();
    die "Invalid expression\n" if $i != length($src);
    return $v->bstr;
}
1;
