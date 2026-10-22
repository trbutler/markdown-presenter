use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MdPresenter::Scripture qw(parseReference fetchVerses versesToMarkdown scriptureMarkdown findDiatheke);

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

my $fake = "$FindBin::Bin/bin/fake-diatheke";
ok(-x $fake, 'fake diatheke is executable');

# Missing tool: a clear message, no silent empty slide.
{
    my $ref = parseReference('John 3:16-18 (KJV)');
    my $v = eval { fetchVerses($ref, diatheke => "$FindBin::Bin/bin/no-such-tool") };
    ok(!$v, 'fails without diatheke');
    like($@, qr/needs diatheke.*not installed/s, 'says diatheke is missing');
    like($@, qr/John 3:16-18 \(KJV\)/, 'names the reference');
}

{
    local $ENV{PATH} = "$FindBin::Bin/fixtures";
    local $ENV{MDP_DIATHEKE};
    is(findDiatheke(), undef, 'not found on an empty PATH');
}

my $ref = parseReference('John 3:16-18 (KJV)');
my $verses = fetchVerses($ref, diatheke => $fake);
is(scalar @$verses, 3, 'three verses');
is($verses->[0]{verse}, 16, 'first verse number');
like($verses->[2]{text}, qr/condemned already, because he hath not believed/, 'continuation line joined');
unlike($verses->[2]{text}, qr/\(KJV\)/, 'module trailer dropped');

{
    local $ENV{MDP_DIATHEKE} = $fake;
    my $ps = fetchVerses(parseReference('Psalm 23:1'));
    is($ps->[0]{text}, 'The LORD is my shepherd; I shall not want.', 'pilcrow stripped, env var honoured');
}

{
    my $v = eval { fetchVerses(parseReference('John 3:16-18 (NOPE)'), diatheke => $fake) };
    ok(!$v, 'empty output fails');
    like($@, qr/no verses for John 3:16-18 in module NOPE/, 'says the module gave nothing');
    $v = eval { fetchVerses(parseReference('John 3:16-18 (FAIL)'), diatheke => $fake) };
    like($@, qr/diatheke failed \(exit 3\).*fake failure/, 'nonzero exit reported');
}

# Slides: never split a verse, keep each slide near the budget.
my $one = versesToMarkdown($ref, $verses, slideChars => 1000);
is(() = $one =~ /^---$/mg, 0, 'one slide when it fits');
like($one, qr/^## John 3:16-18 \(KJV\)$/m, 'kicker names the range and module');
like($one, qr/\x{b9}\x{2076}For God so loved/, 'superscript verse number');

my $split = versesToMarkdown($ref, $verses, slideChars => 150);
my @slides = split /\n---\n/, $split;
is(scalar @slides, 3, 'three slides at a small budget');
like($slides[0], qr/^## John 3:16 \(KJV\)$/m, 'per-slide label, single verse');
like($slides[2], qr/^## John 3:18 \(KJV\)$/m, 'last slide label');

my $two = versesToMarkdown($ref, $verses, slideChars => 260);
like($two, qr/^## John 3:16-17 \(KJV\)$/m, 'two verses share a slide');

my $md = scriptureMarkdown('Jn 3:16-18', diatheke => $fake, slideChars => 1000);
like($md, qr/\(KJV\)/, 'scriptureMarkdown end to end');

done_testing();
