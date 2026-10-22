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

# Runs t/browser/harness-fixes.html in headless Chromium: regression checks
# for the hub 1213+1214 template fixes (black on an auto-advancing deck, the
# number buffer, late-join replies, an empty deck, the in-app waiting state).
# Skipped when no Chromium is installed. Everything it writes stays under
# build/ in the checkout.

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

my $build = "$root/build/browser-fixes";
# Chromium puts its singleton socket under TMPDIR, and a Unix socket path
# must fit in 107 bytes, so the scratch folder sits as high as it can.
my $scratch = "$root/build/tmp";
make_path("$build/profile", $scratch);
my %deck;
foreach my $name (qw(service auto empty)) {
    $deck{$name} = "$build/$name.html";
    local $ENV{MDP_DIATHEKE} = "$root/t/bin/fake-diatheke";
    my $rc = system($^X, "$root/generate.pl", "$root/t/fixtures/deck/$name.md", $deck{$name});
    is($rc, 0, "$name deck built");
}

my $harness = "file://$root/t/browser/harness-fixes.html?" . join('&', map { "$_=file://$deck{$_}" } qw(service auto empty));
local $ENV{TMPDIR} = $scratch;
my @cmd = ($chrome, '--headless', '--no-sandbox', '--disable-gpu',
    '--allow-file-access-from-files', "--user-data-dir=$build/profile",
    '--virtual-time-budget=60000', '--dump-dom', $harness);
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
ok(scalar @$checks >= 18, 'ran the fix checks (' . scalar(@$checks) . ')');
foreach my $c (@$checks) {
    ok($c->{ok}, "browser: $c->{name}") or diag "got: " . ($c->{got} // '');
}

done_testing();
