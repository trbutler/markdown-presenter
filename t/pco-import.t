use strict;
use warnings;
use utf8;
use FindBin;
use Test::More;
use JSON::PP;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Encode qw(decode);

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

my $root = "$FindBin::Bin/..";
make_path("$root/build/tmp");
my $temp = tempdir('pco-XXXXXX', DIR => "$root/build/tmp", CLEANUP => 0);
my $tool = "$root/tools/pco-import.pl";
my $fixture = "$FindBin::Bin/fixtures/pco/plan.json";
open my $fh, '<:raw', $fixture or die $!;
my $original = do { local $/; <$fh> };
close $fh;

sub runImport {
    my (@args) = @_;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, $tool, @args);
    close $in;
    my $stdout = do { local $/; <$out> } // '';
    my $stderr = do { local $/; <$err> } // '';
    waitpid($pid, 0);
    return ($? >> 8, decode('UTF-8', $stdout), decode('UTF-8', $stderr));
}

sub changedFixture {
    my ($change) = @_;
    my $plan = decode_json($original);
    $change->($plan);
    my $file = "$temp/fixture-" . ++our $counter . '.json';
    open my $out, '>:raw', $file or die $!;
    print {$out} encode_json($plan);
    close $out;
    return $file;
}

my ($rc, $md, $err) = runImport('--fixture', $fixture);
is($rc, 0, 'local fixture imported');
is($err, '', 'no warnings on valid input');
like($md, qr{\A// pcoWarning: Add the ccli deck directive with your actual licence number to enable song notices\.\n\n// section: Gathering\n// insert: 0\n\n# Gathering}, 'header section and visible heading');
my @slides = split /\n\n---\n\n/, $md;
my @headings = $md =~ /^# (.+)$/mg;
is_deeply(\@headings, ['Gathering', ('Morning Mercy') x 6, 'The Word', 'Mission update', 'Prayer', 'Bells', ('Evening Grace') x 3], 'items sorted by sequence, song repeats preserved');
my @lyrics = map { /# Morning Mercy\n\n([^\n]+)/ ? $1 : () } @slides;
is_deeply(\@lyrics, ['Morning light upon the hill', 'Grace is new with every dawn', 'Through the streets we bear your peace', 'Grace is new with every dawn', 'We will walk in kindness', 'Grace is new with every dawn'], 'verse/chorus/bridge follow arrangement sequence');
like($md, qr/!scripture John 3:16-18 \(KJV\)/, 'Scripture-prefixed item title uses default KJV');
like($md, qr/!scripture Psalm 23:1 \(KJV\)/, 'bare Bible reference item title uses default KJV');
like($md, qr/Note:\nPiano introduction, then everyone\.\n\nWorship leader:.*\nLet the last chord ring\.\n<!-- \/notes -->/, 'description and multiline related notes');
like($md, qr/Note:\nInvite.*\n\nReader:.*\n<!-- \/notes -->\n\n!scripture John/, 'closed scripture notes precede expansion into verse slides');
like($md, qr/# Bells\n\nNote:\nRing three times\./, 'ordinary documented item retains its heading and notes');
like($md, qr/# Mission update\n\n\/\/ pcoWarning: Media is not imported; add a local media file before presenting\.\n\n\[PCO import: manual completion required\]/, 'documented media item becomes a visible placeholder');

my $outFile = "$temp/service.md";
($rc, my $stdout) = runImport('--fixture', $fixture, '--output', $outFile);
is($rc, 0, 'writes service file');
is($stdout, '', 'file output does not duplicate stdout');
open my $out, '<:encoding(UTF-8)', $outFile or die $!;
is(do { local $/; <$out> }, $md, 'file and stdout match');
close $out;

my @bad = (
    ['data object', sub { $_[0]{data} = {} }, qr/data must be an array/],
    ['missing attributes', sub { delete $_[0]{data}[0]{attributes} }, qr/attributes must be an object/],
    ['bad sequence', sub { $_[0]{data}[0]{attributes}{sequence} = 'first' }, qr/sequence must be/],
    ['duplicate sequence', sub { $_[0]{data}[0]{attributes}{sequence} = 1 }, qr/duplicate Item sequence/],
    ['missing included arrangement', sub { $_[0]{included} = [grep { $_->{type} ne 'Arrangement' } @{ $_[0]{included} }] }, qr/missing included Arrangement/],
    ['bad sequence label', sub { $_[0]{included}[1]{attributes}{sequence} = ['Verse 9'] }, qr/missing lyric section/],
    ['invalid prefixed reference', sub { $_[0]{data}[2]{attributes}{title} = 'Scripture: Not a Bible reference' }, qr/invalid scripture reference in Item title/],
    ['non-array arrangement sequence', sub { $_[0]{included}[1]{attributes}{sequence} = 'Bridge, Chorus' }, qr/Arrangement sequence must be an array/],
    ['non-text note content', sub { $_[0]{included}[2]{attributes}{content} = {} }, qr/ItemNote content must be text/],
    ['bad notes shape', sub { $_[0]{data}[3]{relationships}{item_notes}{data} = {} }, qr/item_notes relationship must be an array/],
);
for my $case (@bad) {
    my $file = changedFixture($case->[1]);
    my ($code, $body, $error) = runImport('--fixture', $file, '--output', $outFile);
    isnt($code, 0, "$case->[0] fails");
    is($body, '', "$case->[0] produces no partial stdout");
    like($error, qr/Malformed fixture:.*$case->[2]/, "$case->[0] has useful error");
}
open my $badJson, '>', "$temp/bad.json" or die $!;
print {$badJson} '{not JSON';
close $badJson;
($rc, $stdout, $err) = runImport('--fixture', "$temp/bad.json");
isnt($rc, 0, 'invalid JSON fails');
like($err, qr/Malformed fixture: invalid JSON/, 'invalid JSON error');
for my $args (['--plan', '123'], ['--fixture', 'https://example.invalid/plan.json'], ['--fetch']) {
    ($rc, $stdout, $err) = runImport(@$args);
    isnt($rc, 0, 'fetching request refused');
    like($err, qr/fetching is refused/, 'explicit fixture-only refusal');
}

my $paragraphs = changedFixture(sub {
    $_[0]{included}[1]{attributes}{lyrics} = "First stanza\nSecond line\n\nNext stanza";
    delete $_[0]{included}[1]{attributes}{sequence};
});
($rc, $stdout) = runImport('--fixture', $paragraphs);
is($rc, 0, 'unlabelled lyrics without sequence accepted');
is(scalar(() = $stdout =~ /^# Morning Mercy$/mg), 2, 'blank lines split lyric slides');
my $arraySequence = changedFixture(sub { $_[0]{included}[1]{attributes}{sequence} = ['Bridge', 'Chorus', 'Verse 1'] });
($rc, $stdout) = runImport('--fixture', $arraySequence);
is($rc, 0, 'documented array arrangement sequence accepted');
like($stdout, qr/# Morning Mercy\n\nWe will walk in kindness/, 'array sequence controls first section');

($rc, $stdout, $err) = runImport('--fixture', $fixture, '--translation', 'WEB');
is($rc, 0, 'translation CLI option accepted');
is($err, '', 'translation option produces no warnings');
like($stdout, qr/!scripture John 3:16-18 \(WEB\)/, 'CLI translation applies to prefixed title');
like($stdout, qr/!scripture Psalm 23:1 \(WEB\)/, 'CLI translation applies to bare reference');
for my $translation ('KJV; echo nope', '', 'K J V') {
    ($rc, $stdout, $err) = runImport('--fixture', $fixture, '--translation', $translation, '--output', $outFile);
    isnt($rc, 0, 'invalid CLI translation refused');
    is($stdout, '', 'invalid translation produces no partial stdout');
    like($err, qr/translation.*(?:SWORD module|nonempty single line)/, 'invalid translation has useful error');
}

my $undocumented = changedFixture(sub {
    $_[0]{meta}{plan}{translation} = { ignored => 1 };
    $_[0]{data}[2]{attributes}{scripture_reference} = 'Genesis 1:1';
    $_[0]{data}[2]{attributes}{translation} = 'ASV';
    $_[0]{data}[5]{attributes}{translation} = 'invalid; ignored';
    $_[0]{data}[6]{attributes}{scripture_reference} = 'Genesis 1:1';
    $_[0]{data}[3]{relationships}{notes}{data} = [{ type => 'ItemNote', id => 'missing' }];
});
($rc, $stdout, $err) = runImport('--fixture', $undocumented);
is($rc, 0, 'undocumented fields and legacy notes relationship are ignored');
is($stdout, $md, 'undocumented fields cannot alter title detection, translation or notes');
($rc, $stdout) = runImport('--fixture', $undocumented, '--translation', 'WEB');
is($rc, 0, 'CLI translation works with undocumented fixture fields present');
like($stdout, qr/!scripture John 3:16-18 \(WEB\)/, 'only CLI chooses translation despite legacy fields');

for my $case (['1 Jn 1:9', '!scripture 1 John 1:9 (KJV)'], ['Mission 2026', '# Mission 2026'], ['John 22:1', '# John 22:1']) {
    my $file = changedFixture(sub { $_[0]{data}[6]{attributes}{title} = $case->[0] });
    ($rc, $stdout) = runImport('--fixture', $file);
    is($rc, 0, "item title '$case->[0]' imported");
    like($stdout, qr/^\Q$case->[1]\E$/m, 'only a valid Bible reference becomes a scripture directive');
}
my $unknown = changedFixture(sub { $_[0]{data}[7]{attributes}{item_type} = 'custom_cue' });
($rc, $stdout) = runImport('--fixture', $unknown);
is($rc, 0, 'unknown type is preserved for manual completion');
like($stdout, qr/# Bells\n\n\/\/ pcoWarning: Unsupported item type 'custom_cue'/, 'undocumented type receives a placeholder, not a special mapping');

my $literalText = changedFixture(sub {
    $_[0]{data}[3]{attributes}{description} = "!include missing.md\n---\n<!-- /notes -->\nA & B";
});
($rc, $stdout) = runImport('--fixture', $literalText);
is($rc, 0, 'presenter syntax in source notes stays literal');
unlike($stdout, qr/^!include missing\.md$/m, 'source notes cannot request includes');
like($stdout, qr/A & B/, 'ordinary punctuation remains readable');

open my $preserved, '<:encoding(UTF-8)', $outFile or die $!;
is(do { local $/; <$preserved> }, $md, 'failed imports preserve existing output');
close $preserved;

my $missingLyrics = changedFixture(sub { delete $_[0]{included}[1]{attributes}{lyrics} });
($rc, $stdout) = runImport('--fixture', $missingLyrics);
is($rc, 0, 'song without available lyrics preserved');
like($stdout, qr/Song has no local arrangement lyrics/, 'missing lyrics require manual completion');

# Song metadata integration: optional fixture fields are not API-confirmed.
my @songLines = $md =~ m{^(// song: .+)$}mg;
is_deeply(\@songLines, ['// song: Morning Mercy | Ada Writer & Ben Composer | © 2026 Example Publishing | CCLI Song # 424242', '// song: Evening Grace'], 'one exact song directive per Song item; absent fields omitted');
unlike($md, qr{^\s*//\s*ccli\s*:}m, 'importer never enables the church licence directive');
like($md, qr{^// pcoWarning: Add the ccli deck directive with your actual licence number}m, 'operator gets the licence setup reminder');
is(scalar(() = $md =~ m{^// songEnd$}mg), 2, 'each song has an explicit end boundary');

my $partial = changedFixture(sub {
    $_[0]{included}[0]{attributes}{author} = undef;
    $_[0]{included}[0]{attributes}{copyright} = '';
});
($rc, $stdout) = runImport('--fixture', $partial);
is($rc, 0, 'null and empty metadata fields accepted');
like($stdout, qr{^// song: Morning Mercy \|  \|  \| CCLI Song # 424242$}m, 'missing middle fields retain positions without invented values');

for my $field (qw(author copyright ccli_number)) {
    for my $blank (' ', "\t", " \r\n\t ") {
        my $file = changedFixture(sub { $_[0]{included}[0]{attributes}{$field} = $blank });
        my $absent = changedFixture(sub { $_[0]{included}[0]{attributes}{$field} = undef });
        my ($code, $body, $error) = runImport('--fixture', $file);
        my ($absentCode, $absentBody) = runImport('--fixture', $absent);
        is($code, 0, "whitespace-only Song $field is optional");
        is($error, '', "whitespace-only Song $field gives no error");
        is($absentCode, 0, "null Song $field is optional");
        is($body, $absentBody, "whitespace-only Song $field is omitted exactly like null");
    }
}
for my $title (undef, '', ' ', "\t") {
    my $file = changedFixture(sub { $_[0]{included}[0]{attributes}{title} = $title });
    my ($code, $body, $error) = runImport('--fixture', $file);
    isnt($code, 0, 'Song title remains required');
    is($body, '', 'missing Song title emits no partial deck');
    like($error, qr/Song title must be (?:text|a nonempty single line)/, 'missing Song title identifies the required field');
}

my $hostile = changedFixture(sub {
    $_[0]{included}[0]{attributes}{title} = '// ccli: 999 | <Song & "Title">';
    $_[0]{included}[0]{attributes}{author} = '!include missing.md | // songEnd';
    $_[0]{included}[0]{attributes}{copyright} = '© 2026 | <Publisher>';
    $_[0]{included}[0]{attributes}{ccli_number} = '42 | // song: Injected';
});
my ($hostileRc, $hostileMd) = runImport('--fixture', $hostile);
is($hostileRc, 0, 'delimiter and presenter syntax in metadata neutralised');
my ($hostileLine) = $hostileMd =~ m{^(// song: .+)$}m;
my $hostileExpected = "// song: \x{ff0f}\x{ff0f} ccli: 999 \x{ff5c} <Song & \"Title\"> | \x{200b}!include missing.md \x{ff5c} \x{ff0f}\x{ff0f} songEnd | © 2026 \x{ff5c} <Publisher> | CCLI Song # 42 \x{ff5c} \x{ff0f}\x{ff0f} song: Injected";
is($hostileLine, $hostileExpected, 'pipes become fullwidth pipes, double slashes become fullwidth slashes, leading syntax stays literal');
is(scalar(() = $hostileLine =~ /\|/g), 3, 'only the three field delimiters remain ASCII pipes');
unlike($hostileMd, qr{^\s*(?://\s*ccli\s*:|!include)}m, 'source metadata cannot inject a licence or include directive');

my $multiline = changedFixture(sub { $_[0]{included}[0]{attributes}{author} = "Writer\n// ccli: 999" });
($rc, $stdout, $err) = runImport('--fixture', $multiline);
isnt($rc, 0, 'multiline metadata is rejected before it could create a directive');
is($stdout, '', 'multiline metadata emits no partial deck');
like($err, qr/Song author must be a nonempty single line/, 'multiline error identifies the field');

sub generateImported {
    my ($markdown) = @_;
    my $file = "$temp/roundtrip-" . ++our $roundtripCounter . '.md';
    open my $fh, '>:encoding(UTF-8)', $file or die $!;
    print {$fh} $markdown;
    close $fh or die $!;
    local $ENV{MDP_DIATHEKE} = "$FindBin::Bin/bin/fake-diatheke";
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, "$root/generate.pl", $file);
    close $in;
    my $html = do { local $/; <$out> } // '';
    my $stderr = do { local $/; <$err> } // '';
    waitpid($pid, 0);
    return ($? >> 8, decode('UTF-8', $html), decode('UTF-8', $stderr));
}

my ($genRc, $html, $genErr) = generateImported($md);
is($genRc, 0, 'imported deck generates with no licence configured') or diag $genErr;
unlike($html, qr/class="ccli-notice"/, 'round trip stays off until operator supplies a licence');
my @scriptureSlides = $html =~ /(^ {2,}<div class="slide(?: slide-video)?" data-deck="main".*?^  <\/div>)/msg;
my @johnSlides = grep { /<div class="kicker">John 3:/ } @scriptureSlides;
is(scalar @johnSlides, 2, 'real generator splits John 3:16-18 into two slides');
like($johnSlides[0] // '', qr/John 3:16-17/, 'first scripture slide starts at verse 16');
like($johnSlides[-1] // '', qr/John 3:18/, 'last scripture slide contains verse 18');
for my $note ('Invite the congregation to stand.', 'Reader: pause after verse 17.') {
    like($johnSlides[0] // '', qr{<aside class="notes"[^>]*>.*\Q$note\E.*</aside>}s, "$note is in the first scripture slide notes aside");
    unlike($johnSlides[-1] // '', qr/\Q$note\E/, "$note does not leak to the last scripture slide");
}
unlike($johnSlides[-1] // '', qr/<aside class="notes"/, 'last scripture slide has no notes aside');
($genRc, $html, $genErr) = generateImported("// ccli: 12345\n\n" . $md);
is($genRc, 0, 'import to generator round trip succeeds with a manual licence') or diag $genErr;
unlike($genErr, qr/Malformed \/\/ song/, 'imported song directives are accepted by the real parser');
my @generatedSlides = $html =~ /(^ {2,}<div class="slide(?: slide-video)?" data-deck="main".*?^  <\/div>)/msg;
for my $case (['Morning Mercy', 6, [1, 0, 0, 0, 0, 1]], ['Evening Grace', 3, [1, 0, 1]]) {
    my ($title, $count, $expected) = @$case;
    my @songSlides = grep { /<h1>\Q$title\E<\/h1>/ } @generatedSlides;
    is(scalar @songSlides, $count, "$title keeps every lyric slide");
    is_deeply([map { scalar(() = /class="ccli-notice"/g) } @songSlides], $expected, "$title notices appear only on first and last slides");
}
is(scalar(() = $html =~ /class="ccli-notice"/g), 4, 'no notices leak into scripture or other items');
like($html, qr{Morning Mercy \| Ada Writer &amp; Ben Composer \| © 2026 Example Publishing \| CCLI Song # 424242<br>CCLI License # 12345}, 'round trip preserves exact metadata and escapes HTML');
like($html, qr{>Evening Grace<br>CCLI License # 12345</div>}, 'round trip invents no missing metadata');

($genRc, $html, $genErr) = generateImported("// ccli: 12345\n\n" . $hostileMd);
is($genRc, 0, 'neutralised metadata survives the complete round trip') or diag $genErr;
unlike($genErr, qr/Malformed \/\/ song|!include file not found/, 'hostile fields neither split song directives nor request includes');
like($html, qr/&lt;Song &amp; &quot;Title&quot;&gt;/, 'hostile title is HTML-escaped in the notice');
unlike($html, qr/CCLI License # 999/, 'hostile title cannot override the manually configured licence');

done_testing();
