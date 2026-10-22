use strict;
use warnings;
use utf8;
use FindBin;
use Test::More;
use JSON::PP;
use IPC::Open3;
use Symbol qw(gensym);
use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Temp qw(tempdir);

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

my $root = "$FindBin::Bin/..";
my $deck = "$FindBin::Bin/fixtures/deck";
my $fake = "$FindBin::Bin/bin/fake-diatheke";
make_path("$root/build/tmp");
my $temp = tempdir('lowerthird-XXXXXX', DIR => "$root/build/tmp", CLEANUP => 0);

sub writeFixture {
    my ($file, $text) = @_;
    open my $out, '>:encoding(UTF-8)', $file or die $!;
    print {$out} $text;
    close $out or die $!;
    return $file;
}

sub generate {
    my ($file, %env) = @_;
    local @ENV{ keys %env } = values %env;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, "$root/generate.pl", $file);
    close $in;
    binmode $out, ':encoding(UTF-8)';
    binmode $err, ':encoding(UTF-8)';
    my $html = do { local $/; <$out> };
    my $stderr = do { local $/; <$err> };
    waitpid $pid, 0;
    return ($? >> 8, $html // '', $stderr // '');
}

my ($rc, $html, $stderr) = generate("$deck/service.md", MDP_DIATHEKE => $fake);
is($rc, 0, 'service deck builds') or diag $stderr;
is($stderr, '', 'no warnings (new directives are known)');

my ($json) = $html =~ /const deck = (\{.*?\});\n/;
ok($json, 'deck config present');
my $config = decode_json($json);
is(scalar @{ $config->{sections} }, 3, 'three sections');
my ($pre, $worship, $post) = @{ $config->{sections} };
is($pre->{name}, 'Pre-service', 'pre-service name');
is($pre->{cycle}, 8000, 'cycle in ms');
is($pre->{countdown}, '10:30', 'countdown normalised to 24h');
is($pre->{countdownLabel}, 'Worship begins in', 'countdown label');
is($pre->{countdownEnd}, 'next', 'countdownEnd');
is($worship->{cycle}, undef, 'worship does not cycle');
is($post->{cycle}, 10000, 'post-service cycle');

my @slides = $html =~ /<div class="slide[^"]*" data-deck="main"[^>]*data-section-index="(\d)"/g;
is_deeply(\@slides, [0, 0, 1, 1, 1, 1, 2, 2], 'slides per section: 2 announcements; welcome, 2 scripture, sermon; 2 announcements');

like($html, qr/<aside class="notes" aria-hidden="true">\n      <p>Greet visitors\.<\/p>\n      <p>Mention the potluck\.<\/p>\n    <\/aside>/, 'Note: block becomes two paragraphs');
like($html, qr/<p>Point one &amp; two<\/p>/, '<!-- notes --> block, escaped');
like($html, qr/<li>after notes<\/li>/, 'content after <!-- \/notes --> is still slide content');
like($html, qr/<p>Mention the sign-up sheet in the lobby\.<\/p>/, 'notes inside an included file');
unlike($html, qr/<p class="subtitle">[^<]*Greet/, 'notes never reach the slide text');
like($html, qr/<div class="kicker">John 3:16-17 \(KJV\)<\/div>/, 'scripture slide kicker, first chunk');
like($html, qr/<div class="kicker">John 3:18 \(KJV\)<\/div>/, 'scripture splits at the default budget');
like($html, qr/<p class="subtitle">\x{b9}\x{2076}For God so loved/, 'scripture verse text');
like($html, qr/id="servicePanel"/, 'service panel element');
like($html, qr/id="notesPanel"/, 'notes panel element');

($rc, $html, $stderr) = generate("$deck/lowerthird-still.md");
is($rc, 0, 'non-video lower-third deck builds') or diag $stderr;
is($stderr, '', 'non-video lower third has no warning');
like($html, qr/<div class="lower-third" data-build-in="2000" data-build-out="9000">\s*<div class="lt-window">\s*<div class="lt-bar">\s*<div class="lt-name">Ada Lovelace<\/div>\s*<div class="lt-title">Mathematician<\/div>/,
    'non-video slide gets the usual lower-third markup and timing');
like($html, qr/startLowerThird\(slide\);\s*if \(slide\.dataset\.kind === 'video'\) \{\s*const fit/,
    'all slides start lower-third timing while video setup stays video-only');

for my $case (['title', 'Presenter'], ['buildIn', '2s'], ['buildOut', '9s']) {
    my ($key, $value) = @$case;
    my $file = writeFixture("$temp/unnamed-$key.md", "// $key: $value\n\n# Still slide\n");
    ($rc, $html, $stderr) = generate($file);
    is($rc, 0, "unnamed still slide with $key still builds");
    like($stderr, qr{unnamed-\Q$key\E\.md:1: Lower third on a still slide needs // name:}, "$key without name warns with source file and line");
    unlike($html, qr/<div class="lower-third"/, "$key alone does not create a still-slide lower third");

    $file = writeFixture("$temp/named-$key.md", "// $key: $value\n// name: Ada\n\n# Still slide\n");
    ($rc, $html, $stderr) = generate($file);
    is($rc, 0, "named still slide with $key builds");
    is($stderr, '', "named still slide with $key does not warn");

    $file = writeFixture("$temp/video-$key.md", "// video: local.mp4\n// $key: $value\n");
    ($rc, $html, $stderr) = generate($file);
    is($rc, 0, "video with $key and no name builds");
    is($stderr, '', "video with $key keeps its no-warning behavior");
    like($html, qr/<div class="lower-third"/, "video with $key keeps its lower third");
}
my $includedWarning = writeFixture("$temp/include.md", "!include unnamed-title.md\n");
($rc, $html, $stderr) = generate($includedWarning);
is($rc, 0, 'included unnamed lower-third directive builds');
like($stderr, qr{unnamed-title\.md:1: Lower third on a still slide needs // name:}, 'warning uses the included source location');

open my $templateFile, '<:encoding(UTF-8)', "$root/template.html" or die $!;
my $template = do { local $/; <$templateFile> };
close $templateFile;
my @hooks = (
    ['reset', "if (slide.dataset.kind !== 'video') clearLowerThird();"],
    ['timing', "if (slide.dataset.kind === 'video') {\n      startLowerThird(slide);"],
);
for my $hook (@hooks) {
    my ($label, $target) = @$hook;
    my $custom = $template;
    my $changed = $custom =~ s/\Q$target\E/\/\/ Hook removed for regression test/;
    is($changed, 1, "$label test removes an actual patch target");
    my $directory = "$temp/missing-$label";
    make_path($directory);
    writeFixture("$directory/template.html", $custom);
    my $previous = getcwd();
    chdir $directory or die $!;
    ($rc, $html, $stderr) = generate("$deck/lowerthird-still.md");
    chdir $previous or die $!;
    isnt($rc, 0, "missing $label hook stops still-slide lower-third generation");
    is($html, '', "missing $label hook emits no partial HTML");
    like($stderr, qr/Cannot enable still-slide lower thirds: template \Q$label\E hook not found/, "missing $label hook has a clear error");

    my $plain = writeFixture("$temp/plain.md", "# Plain slide\n");
    chdir $directory or die $!;
    ($rc, $html, $stderr) = generate($plain);
    chdir $previous or die $!;
    is($rc, 0, "deck without still-slide lower thirds does not require $label hook");
    is($stderr, '', "unused $label hook produces no error or warning");
}

($rc, $html, $stderr) = generate("$deck/service.md", MDP_DIATHEKE => "$FindBin::Bin/bin/no-such-tool");
isnt($rc, 0, 'missing diatheke stops the build');
like($stderr, qr/service\.md:\d+: !scripture John 3:16-18 \(KJV\) needs diatheke/, 'and says where and why');
is($html, '', 'no half-built deck on stdout');

($rc, $html, $stderr) = generate("$deck/escape.md");
isnt($rc, 0, 'include escape stops the build');
like($stderr, qr/escape\.md:3: !include path may not use \.\./, 'escape reason');

($rc, $html, $stderr) = generate("$deck/bad-countdown.md");
like($stderr, qr/Bad countdown: 25:00/, 'bad countdown time');
($rc, $html, $stderr) = generate("$deck/bad-countdown-end.md");
like($stderr, qr/Bad countdownEnd: later/, 'bad countdownEnd');

# Tim's sample still builds the same way (no new warnings).
($rc, $html, $stderr) = generate("$root/sample.md");
is($rc, 0, 'sample.md builds');
is($stderr, '', 'sample.md has no warnings');

# The macOS app fixture (hub 1214) uses "Notes:" on its own line and
# "Note:" with the text on the same line.
($rc, $html, $stderr) = generate("$root/macos/fixtures/1214-demo.md");
is($rc, 0, '1214 demo builds') or diag $stderr;
like($html, qr/<p>Welcome everyone\. Mention the prayer walk sign-up sheet\.<\/p>\n      <p>Second paragraph of notes, with &lt;angle brackets&gt; &amp; ampersands\.<\/p>/, 'Notes: block, two paragraphs, escaped');
like($html, qr/<aside class="notes" aria-hidden="true">\n      <p>Close in prayer\.<\/p>/, 'Note: text on the same line');
unlike($html, qr/<li>[^<]*Close in prayer/, 'notes never become bullets');

done_testing();
