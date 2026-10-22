use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MdPresenter::Scripture qw(parseReference);

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

sub ranges {
    my ($ref) = @_;
    return [ map {
        my $r = $_;
        join '.', map { defined $r->{$_} ? $r->{$_} : '*' } qw(startChapter startVerse endChapter endVerse);
    } @{ $ref->{ranges} } ];
}

my @ok = (
    # input, book, translation, display, ranges
    ['John 3:16-18 (KJV)', 'John', 'KJV', 'John 3:16-18', ['3.16.3.18']],
    ['John 3:16', 'John', 'KJV', 'John 3:16', ['3.16.3.16']],
    ['Jn 3:16 (WEB)', 'John', 'WEB', 'John 3:16', ['3.16.3.16']],
    ['john 3 : 16 - 18', 'John', 'KJV', 'John 3:16-18', ['3.16.3.18']],
    ["John 3:16\x{2013}18", 'John', 'KJV', 'John 3:16-18', ['3.16.3.18']],
    ['1 John 1:9', '1 John', 'KJV', '1 John 1:9', ['1.9.1.9']],
    ['1Jn 1:9', '1 John', 'KJV', '1 John 1:9', ['1.9.1.9']],
    ['I John 1:9', '1 John', 'KJV', '1 John 1:9', ['1.9.1.9']],
    ['First John 1:9', '1 John', 'KJV', '1 John 1:9', ['1.9.1.9']],
    ['1 Cor. 13:4-7', '1 Corinthians', 'KJV', '1 Corinthians 13:4-7', ['13.4.13.7']],
    ['Psalm 23', 'Psalms', 'KJV', 'Psalm 23', ['23.*.23.*']],
    ['Ps 23:1-3', 'Psalms', 'KJV', 'Psalm 23:1-3', ['23.1.23.3']],
    ['Psalms 1-2', 'Psalms', 'KJV', 'Psalms 1-2', ['1.*.2.*']],
    ['Romans 8:28, 31', 'Romans', 'KJV', 'Romans 8:28, 31', ['8.28.8.28', '8.31.8.31']],
    ['Rom 8:28,31-39', 'Romans', 'KJV', 'Romans 8:28, 31-39', ['8.28.8.28', '8.31.8.39']],
    ['John 3:16; 4', 'John', 'KJV', 'John 3:16; 4', ['3.16.3.16', '4.*.4.*']],
    ['Matthew 5:1-7:29', 'Matthew', 'KJV', 'Matthew 5:1-7:29', ['5.1.7.29']],
    ['Jude 3', 'Jude', 'KJV', 'Jude 3', ['1.3.1.3']],
    ['Jude 3-5', 'Jude', 'KJV', 'Jude 3-5', ['1.3.1.5']],
    ['Jude 1:3', 'Jude', 'KJV', 'Jude 1:3', ['1.3.1.3']],
    ['Philemon 4', 'Philemon', 'KJV', 'Philemon 4', ['1.4.1.4']],
    ['Phil 4:13', 'Philippians', 'KJV', 'Philippians 4:13', ['4.13.4.13']],
    ['Song of Songs 2:4', 'Song of Solomon', 'KJV', 'Song of Solomon 2:4', ['2.4.2.4']],
    ['Deuter 6:4', 'Deuteronomy', 'KJV', 'Deuteronomy 6:4', ['6.4.6.4']],
    ['Rev 22:20 (ASV)', 'Revelation', 'ASV', 'Revelation 22:20', ['22.20.22.20']],
    ['3 John 4', '3 John', 'KJV', '3 John 4', ['1.4.1.4']],
);
foreach my $case (@ok) {
    my ($in, $book, $tr, $display, $ranges) = @$case;
    my $ref = eval { parseReference($in) };
    ok($ref, "parses: $in") or do { diag $@; next };
    is($ref->{book}, $book, "book: $in");
    is($ref->{translation}, $tr, "translation: $in");
    is($ref->{display}, $display, "display: $in");
    is_deeply(ranges($ref), $ranges, "ranges: $in");
}

is(parseReference('John 3:16', defaultTranslation => 'WEB')->{translation}, 'WEB', 'default translation option');
is(parseReference('John 3:16 (BSB)', defaultTranslation => 'WEB')->{translation}, 'BSB', 'explicit beats default');
is(parseReference('1 John 1:9')->{key}, '1 John 1:9', 'diatheke key uses canonical name');

my @bad = (
    ['', qr/Cannot read the reference/],
    ['John', qr/Cannot read the reference/],
    ['Hezekiah 3:16', qr/Unknown book/],
    ['Jo 3:16', qr/ambiguous/],
    ['John 22:1', qr/no chapter 22/],
    ['John 0:1', qr/no chapter 0/],
    ['John 3:0', qr/Verse 0/],
    ['John 3:18-16', qr/backwards/],
    ['John 4-3', qr/backwards/],
    ['John 3:16 (K J V)', qr/Bad translation/],
    ['John 3:16 ($(rm))', qr/Bad translation|Cannot read/],
    ['John 3:16 (rm -rf)', qr/Bad translation/],
    ['John 3::16', qr/Cannot read/],
);
foreach my $case (@bad) {
    my ($in, $re) = @$case;
    my $ref = eval { parseReference($in) };
    ok(!$ref, "rejects: '$in'");
    like($@, $re, "reason for '$in'");
}

done_testing();
