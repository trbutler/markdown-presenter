use strict;
use warnings;
use utf8;
use FindBin;
use Test::More;
use JSON::PP;
use File::Path qw(make_path);
use File::Spec;
use Cwd qw(realpath);
use Encode ();

# Runs t/browser/harness-ltccli.html in headless Chromium: the CCLI notice in
# each view and the operator's L for lower thirds (hub 1213 e). The lower
# third needs a real video, so a short clip is made with ffmpeg; without
# ffmpeg those checks are skipped. Skipped when no Chromium is installed.
# Everything it writes stays under build/.

my $root = realpath("$FindBin::Bin/..");
my $chrome;
foreach my $name ($ENV{MDP_CHROME} // (), qw(chromium chromium-browser google-chrome)) {
    if ($name =~ m{/}) {
        $chrome = $name if -x $name;
    } else {
        ($chrome) = grep { -x $_ } map { File::Spec->catfile($_, $name) } File::Spec->path;
    }
    last if $chrome;
}
plan skip_all => 'no Chromium found' unless $chrome;

my $build = "$root/build/browser-ltccli";
# Chromium puts its singleton socket under TMPDIR, and a Unix socket path
# must fit in 107 bytes, so the scratch folder sits as high as it can.
my $scratch = "$root/build/tmp";
make_path("$build/profile", $scratch);
my %deck;
my $ffmpeg = grep { -x "$_/ffmpeg" } File::Spec->path;
if ($ffmpeg) {
    my $rc = system('ffmpeg', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'color=c=black:s=64x36:d=30:r=10',
        '-c:v', 'libvpx', '-b:v', '20k', "$build/clip.webm");
    $ffmpeg = 0 if $rc;
}
foreach my $name (qw(plain ccli lt ltm)) {
    next if $name =~ /^lt/ && !$ffmpeg;
    $deck{$name} = "$build/$name.html";
    local $ENV{MDP_DIATHEKE} = "$root/t/bin/fake-diatheke";
    my $src = { plain => 'service', ccli => 'ccli', lt => 'lowerthird', ltm => 'lowerthird-manual' }->{$name};
    my $rc = system($^X, "$root/generate.pl", "$root/t/fixtures/deck/$src.md", $deck{$name});
    is($rc, 0, "$name deck built");
}

my $harness = "file://$root/t/browser/harness-ltccli.html?" . join('&', map { "$_=file://$deck{$_}" } grep { $deck{$_} } qw(plain ccli lt ltm));
local $ENV{TMPDIR} = $scratch;
my @cmd = ($chrome, '--headless', '--no-sandbox', '--disable-gpu',
    '--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required', "--user-data-dir=$build/profile",
    '--virtual-time-budget=120000', '--dump-dom', $harness);
open my $fh, '-|', @cmd or die "Cannot run $chrome: $!";
binmode $fh, ':encoding(UTF-8)';
my $dom = do { local $/; <$fh> };
close $fh;

my ($json) = $dom =~ /<pre id="result">(.*?)<\/pre>/s;
ok(defined $json && $json ne 'pending', 'harness finished') or diag substr($dom // '', 0, 2000);
if (defined $json) {
    $json =~ s/&lt;/</g;
    $json =~ s/&gt;/>/g;
    $json =~ s/&quot;/"/g;
    $json =~ s/&amp;/&/g;
}
my $checks = eval { decode_json(Encode::encode('UTF-8', $json)) } || [];
ok(scalar @$checks > 20, 'ran the lower-third and CCLI checks (' . scalar(@$checks) . ')');
foreach my $c (@$checks) {
    ok($c->{ok}, "browser: $c->{name}") or diag "got: " . ($c->{got} // '');
}

done_testing();
