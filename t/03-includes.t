use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use MdPresenter::Expand qw(expandFile);

my $dir = "$FindBin::Bin/fixtures/includes";

my $md = expandFile("$dir/main.md");
like($md, qr/# Child/, 'includes a file in a subfolder');
like($md, qr/- from grandchild/, 'nested include is relative to the including file');
like($md, qr/# Announcements\n\n- Potluck Sunday/, 'quoted include name');
unlike($md, qr/!include/, 'no directive left behind');

my %bad = (
    'sub/dotdot.md'  => qr/sub\/dotdot\.md:1: !include path may not use \.\./,
    'absolute.md'    => qr/absolute\.md:1: !include path must be relative/,
    'missing-ref.md' => qr/missing-ref\.md:1: !include file not found: missing\.md/,
    'symlink.md'     => qr/symlink\.md:1: !include leaves the deck folder/,
    'cycle-start.md' => qr/^cycle\/b\.md:2: Include cycle: cycle-start\.md -> cycle\/a\.md -> cycle\/b\.md -> cycle\/a\.md/,
    'self.md'        => qr/^self\.md:1: Include cycle: self\.md -> self\.md/,
    'empty.md'       => qr/empty\.md:1: !include needs a file name/,
    'dir.md'         => qr/dir\.md:1: !include is not a file: sub/,
);
foreach my $file (sort keys %bad) {
    # The deck root stays the includes folder even when the entry file is
    # deeper, the same as when generate.pl is pointed at the main deck.
    my $out = eval { expandFile("$dir/$file", root => $dir) };
    ok(!defined $out, "refused: $file");
    like($@, $bad{$file}, "reason: $file");
}

# A deck in a subfolder cannot reach its parent, even though the parent is
# where the included file really is.
{
    my $out = eval { expandFile("$dir/sub/dotdot.md") };
    like($@, qr/may not use \.\./, 'root defaults to the entry file folder');
}

# Depth limit.
{
    local $MdPresenter::Expand::maxDepth = 2;
    my $out = eval { expandFile("$dir/main.md") };
    like($@, qr/nested deeper than 2/, 'depth limit');
}

# !scripture is expanded through the injected fetcher; // translation sets
# the default for the lines after it.
{
    my @seen;
    my $fetch = sub {
        my ($ref, %opt) = @_;
        push @seen, [$ref, $opt{defaultTranslation} // ''];
        return "## stub $ref\n";
    };
    my $text = expandFile("$FindBin::Bin/fixtures/deck/scripture-lines.md", scripture => $fetch);
    is_deeply(\@seen, [['John 3:16', ''], ['Psalm 23 (KJV)', 'WEB'], ['Jude 3', 'WEB']], 'scripture lines and default translation');
    like($text, qr/## stub John 3:16/, 'scripture text pasted in');
    my $err = eval { expandFile("$FindBin::Bin/fixtures/deck/scripture-empty.md", scripture => $fetch); 1 } ? '' : $@;
    like($err, qr/scripture-empty\.md:3: !scripture needs a reference/, 'empty scripture line');
    $err = eval { expandFile("$FindBin::Bin/fixtures/deck/scripture-lines.md", scripture => sub { die "boom\n" }); 1 } ? '' : $@;
    like($err, qr/scripture-lines\.md:1: boom/, 'fetch errors carry file and line');
}

done_testing();
