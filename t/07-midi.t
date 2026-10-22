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

# Runs t/browser/harness-midi.html in headless Chromium: MIDI on slide change
# (hub 1213 d) with a fake Web MIDI and a fake WebKit bridge. Skipped when no
# Chromium is installed. Everything it writes stays under build/.

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

my $build = "$root/build/browser-midi";
# Chromium puts its singleton socket under TMPDIR, and a Unix socket path
# must fit in 107 bytes, so the scratch folder sits as high as it can.
my $scratch = "$root/build/tmp";
make_path("$build/profile", $scratch);
my %deck;
foreach my $name (qw(plain midi auto)) {
    $deck{$name} = "$build/$name.html";
    local $ENV{MDP_DIATHEKE} = "$root/t/bin/fake-diatheke";
    my $src = { plain => 'service', midi => 'midi', auto => 'midi-auto' }->{$name};
    my $rc = system($^X, "$root/generate.pl", "$root/t/fixtures/deck/$src.md", $deck{$name});
    is($rc, 0, "$name deck built");
}

# The generator: the deck setting lands in the config only when given; a
# slide's own // midi: becomes data-midi; a bad one stops the build.
{
    my $read = sub { open my $fh, '<:encoding(UTF-8)', $_[0] or die; local $/; <$fh> };
    my $midi = $read->($deck{midi});
    like($midi, qr/"midi":\{"channel":2,"out":"fake"\}/, 'generator: deck midi settings in the config');
    like($midi, qr/data-midi="pc 9"/, 'generator: // midi: pc 9 on its slide');
    like($midi, qr/data-midi="note 3 60"/, 'generator: // midi: note 3 60 on its slide');
    like($midi, qr/data-midi="off"/, 'generator: // midi: off on its slide');
    unlike($read->($deck{plain}), qr/"midi":|data-midi/, 'generator: no midi in a deck without the directive');
    like($read->($deck{auto}), qr/"midi":\{"channel":1,"out":"fake"\}/, 'generator: // midiOut: fake, channel 1');
    my $bad = "$build/bad.md";
    open my $fh, '>', $bad or die;
    print $fh "// midi: on\n\n# One\n\n---\n\n// midi: pc\n\n# Two\n";
    close $fh;
    my $err = `$^X "$root/generate.pl" "$bad" "$build/bad.html" 2>&1`;
    isnt($? >> 8, 0, 'generator: a malformed // midi: stops the build');
    like($err, qr{Bad // midi: pc}, 'generator: and says which');
}

my $harness = "file://$root/t/browser/harness-midi.html?" . join('&', map { "$_=file://$deck{$_}" } qw(plain midi auto));
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
ok(scalar @$checks > 20, 'ran the MIDI checks (' . scalar(@$checks) . ')');
foreach my $c (@$checks) {
    ok($c->{ok}, "browser: $c->{name}") or diag "got: " . ($c->{got} // '');
}

done_testing();
