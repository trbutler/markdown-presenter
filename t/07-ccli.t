use strict;
use warnings;
use utf8;
use FindBin;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

my $root = "$FindBin::Bin/..";
make_path("$root/build/tmp");
my $temp = tempdir('ccli-XXXXXX', DIR => "$root/build/tmp", CLEANUP => 0);
make_path("$temp/sub");

sub writeDeck {
    my ($name, $text) = @_;
    open my $fh, '>:encoding(UTF-8)', "$temp/$name" or die $!;
    print {$fh} $text;
    close $fh or die $!;
    return "$temp/$name";
}

sub generate {
    my ($name, $text) = @_;
    my $file = writeDeck($name, $text);
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, "$root/generate.pl", $file);
    close $in;
    binmode $out, ':encoding(UTF-8)';
    binmode $err, ':encoding(UTF-8)';
    my $html = do { local $/; <$out> } // '';
    my $stderr = do { local $/; <$err> } // '';
    waitpid $pid, 0;
    is($? >> 8, 0, "$name builds") or diag $stderr;
    return ($html, $stderr);
}

sub slides {
    my ($html) = @_;
    return $html =~ /(^ {2,}<div class="slide(?: slide-video)?" data-deck="main".*?^  <\/div>)/msg;
}

sub noticeCount {
    return scalar(() = $_[0] =~ /class="ccli-notice"/g);
}

my $song = <<'MD';
// song: Light <& "Hope"> | A & B | © 2026 <Publisher> | CCLI Song # 42

# First verse

Words one

---

# Middle verse

Words two

Note: Keep this private.
// song: Private song | Private author
// ccli: 999
<!-- /notes -->

---

# Last verse

Words three

---

// songEnd

# Prayer
MD
my ($html, $err) = generate('off.md', $song);
is($err, '', 'song metadata is recognised when notices are off');
is(noticeCount($html), 0, 'absent deck licence produces no notices anywhere');
unlike($html, qr/CCLI License #/, 'off emits no licence line');
unlike($html, qr/Light &lt;/, 'off emits no song metadata');

($html, $err) = generate('on.md', "// ccli: 1234567\n\n" . $song);
is($err, '', 'valid directives generate no warnings');
my @slides = slides($html);
is(scalar @slides, 4, 'three song slides and prayer');
is_deeply([map { noticeCount($_) } @slides], [1, 0, 1, 0], 'only first and last song slide carry notices');
my $expected = 'Light &lt;&amp; &quot;Hope&quot;&gt; | A &amp; B | © 2026 &lt;Publisher&gt; | CCLI Song # 42<br>CCLI License # 1234567';
for my $index (0, 2) {
    like($slides[$index], qr/<div class="ccli-notice" style="font-size: small;">\Q$expected\E<\/div>/, 'exact escaped metadata and licence line');
    unlike($slides[$index], qr/<Publisher>|<script>/, 'notice cannot inject HTML');
}
my ($notes) = $slides[1] =~ /(<aside class="notes".*?<\/aside>)/s;
like($notes, qr/Private song/, 'notes remain notes');
unlike($notes, qr/ccli-notice|CCLI License #/, 'no notice inside notes-only content');
unlike($html, qr/CCLI License # 999/, 'notes cannot enable or change the deck licence');

($html, $err) = generate('boundaries.md', <<'MD');
// ccli: 1234567
// song: Only a title

# One slide song

---

// song: Second | Writer || CCLI Song # 73

# Second song start

---

# Second song end

---

// section: Sermon

# Not a song

---

// song: Third

---

# Third song start

---

# Third song end

---

// type: fillers

# Filler
MD
is($err, '', 'partial metadata and metadata-only blocks are valid');
@slides = slides($html);
is_deeply([map { noticeCount($_) } @slides], [1, 1, 1, 0, 1, 1], 'new songs, section boundary and filler boundary define song runs');
like($slides[0], qr/>Only a title<br>CCLI License # 1234567<\/div>/, 'missing fields are omitted and a single slide has one notice');
like($slides[1], qr/>Second \| Writer \| CCLI Song # 73<br>CCLI License # 1234567<\/div>/, 'empty copyright field is not invented');
unlike($slides[0], qr/©|CCLI Song #/, 'no guessed copyright or song number');
my ($filler) = $html =~ /(^ {2,}<div class="slide" data-deck="filler".*?^  <\/div>)/ms;
is(noticeCount($filler), 0, 'fillers do not inherit a song notice');

# Include expansion preserves song scope and original diagnostic locations.
writeDeck('sub/song.md', "// song: Included | Included writer\n\n# Included first\n\n---\n\n!include last.md\n");
writeDeck('sub/last.md', "# Included last\n");
($html, $err) = generate('include.md', "// ccli: 1234567\n\n!include sub/song.md\n\n---\n\n// songEnd\n# After\n");
is($err, '', 'nested includes carry valid song metadata');
@slides = slides($html);
is_deeply([map { noticeCount($_) } @slides], [1, 1, 0], 'included first and last slides have notices, following slide does not');
like($slides[0], qr/Included \| Included writer<br>CCLI License # 1234567/, 'included metadata is rendered');

writeDeck('sub/bad.md', "# Before bad metadata\n\n---\n\n// song: | Writer\n\n# Missing title\n\n---\n\n// song: Title | Writer | Copyright | Number | Extra\n\n# Too many fields\n");
($html, $err) = generate('bad.md', "// ccli: 1234567\n\n!include sub/bad.md\n");
like($err, qr/^sub\/bad\.md:5: Malformed \/\/ song:/m, 'missing title warns at original included file:line');
like($err, qr/^sub\/bad\.md:11: Malformed \/\/ song:/m, 'extra fields warn at original included file:line');
is(noticeCount($html), 0, 'malformed songs emit no fabricated notice');
($html, $err) = generate('empty.md', "// ccli: 1234567\n\n// song\n# Song\n");
like($err, qr/^empty\.md:3: Malformed \/\/ song:/m, 'missing song value warns at source file:line');

($html, $err) = generate('missing-colon.md', "// ccli: 1234567\n// song Title | Writer\n# Song\n");
like($err, qr/^missing-colon\.md:2: Malformed \/\/ song:/m, 'malformed directive syntax warns with file:line');
is(noticeCount($html), 0, 'malformed directive syntax is not rendered as song metadata');

($html, $err) = generate('invalid-license.md', "// ccli: <script>\n// song: Title\n# Song\n");
like($err, qr/^invalid-license\.md:1: \/\/ ccli needs a licence number; notices disabled/m, 'invalid licence warns with source location');
is(noticeCount($html), 0, 'invalid licence cannot enable notices');

($html, $err) = generate('notes-only.md', "// ccli: 1234567\n\nNote: private\n// song: Hidden\n\n---\n\n# Ordinary slide\n");
is($err, '', 'song-like text inside notes is not a directive');
is(noticeCount($html), 0, 'notes-only metadata never adds notices');

($html, $err) = generate('video.md', "// ccli: 1234567\n// song: Video song\n// video: local.mp4\n");
is($err, '', 'video song builds');
like($html, qr/data-kind="video".*?class="ccli-notice"/s, 'single video song also receives one notice');
is(noticeCount($html), 1, 'single video song notice is not duplicated');

done_testing();
