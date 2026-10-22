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
like($md, qr{\A// section: Gathering\n// insert: 0\n\n# Gathering}, 'header section and visible heading');
my @slides = split /\n\n---\n\n/, $md;
my @headings = $md =~ /^# (.+)$/mg;
is_deeply(\@headings, ['Gathering', ('Morning Mercy') x 6, 'The Word', 'Mission update', 'Prayer', 'Bells'], 'items sorted by sequence, song repeats preserved');
my @lyrics = map { /# Morning Mercy\n\n([^\n]+)/ ? $1 : () } @slides;
is_deeply(\@lyrics, ['Morning light upon the hill', 'Grace is new with every dawn', 'Through the streets we bear your peace', 'Grace is new with every dawn', 'We will walk in kindness', 'Grace is new with every dawn'], 'verse/chorus/bridge follow arrangement sequence');
like($md, qr/!scripture John 3:16-18 \(KJV\)/, 'title scripture with plan translation');
like($md, qr/!scripture Psalm 23:1 \(WEB\)/, 'reference scripture with item translation');
like($md, qr/Note:\nPiano introduction, then everyone\.\n\nWorship leader:.*\nLet the last chord ring\.\n<!-- \/notes -->/, 'description and multiline related notes');
like($md, qr/!scripture John.*\n\nNote:\nInvite.*\n\nReader:/, 'scripture notes attached to scripture block');
like($md, qr/# Bells\n\n\/\/ pcoWarning: Unsupported item type 'custom_cue'/, 'unknown item heading and clear comment');
like($md, qr/# Mission update.*?manual completion required/s, 'media placeholder retained');

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
    ['bad translation', sub { $_[0]{meta}{plan}{translation} = 'KJV; echo nope' }, qr/SWORD module/],
    ['bad notes shape', sub { $_[0]{data}[3]{relationships}{notes}{data} = {} }, qr/notes relationship must be an array/],
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
my $stringSequence = changedFixture(sub { $_[0]{included}[1]{attributes}{sequence} = 'Bridge, Chorus, Verse 1' });
($rc, $stdout) = runImport('--fixture', $stringSequence);
is($rc, 0, 'comma-separated arrangement sequence accepted');
like($stdout, qr/# Morning Mercy\n\nWe will walk in kindness/, 'string sequence controls first section');

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

done_testing();
