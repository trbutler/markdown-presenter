use strict;
use warnings;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use FindBin;
use Mojo::JSON qw(decode_json);
use Mojo::File qw(path);
use Mojo::Server;

my $temp = tempdir(CLEANUP => 1);
local $ENV{PRESENTER_CUES} = "$temp/cues.json";
my $t = Test::Mojo->new(Mojo::Server->new->load_app("$FindBin::Bin/../script/display-server"));
$t->get_ok('/')->status_is(200)->content_like(qr/Live lower-third output/);
$t->get_ok('/output/lower-third')->status_is(200);
$t->get_ok('/api/v1/outputs/lower-third/state')->status_is(200)->json_is('/phase', 'hidden');
$t->get_ok('/api/v1/outputs/unknown/state')->status_is(404);
$t->get_ok('/api/v1/themes')->status_is(200)->json_is('/0/id', 'little-hills');
$t->get_ok('/themes/little-hills/template.html')->status_is(200);
$t->get_ok('/themes/little-hills/assets/logo.svg')->status_is(200);
$t->get_ok('/themes/unknown/style.css')->status_is(404);
$t->get_ok('/var/cues.json')->status_is(404);
$t->get_ok('/script/display-server')->status_is(404);

my $cue = {id => 'test', label => 'Test', theme => 'little-hills', variant => 'regular',
    font => 'quicksand', line1 => '<script>alert(1)</script>', line2 => 'A&B', holdMs => 5000};
$t->post_ok('/api/v1/cues' => json => $cue)->status_is(201)->json_is('/line1', $cue->{line1});
ok -f "$temp/cues.json", 'cue file persisted';
is scalar @{decode_json(path("$temp/cues.json")->slurp)}, 4, 'saved array includes existing examples';
$t->post_ok('/api/v1/cues' => json => $cue)->status_is(409);
$t->post_ok('/api/v1/cues' => json => {%$cue, id => 'invalid', holdMs => -1})->status_is(400);
$t->post_ok('/api/v1/cues' => json => {%$cue, id => 'invalid', theme => '../x'})->status_is(400);
$t->post_ok('/api/v1/cues' => {'Origin' => 'http://evil.invalid'} => json => {%$cue, id => 'origin'})->status_is(403);
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'trigger', cueId => 'test'})
    ->status_is(200)->json_is('/phase', 'entering')->json_is('/run/cue/line1', $cue->{line1})
    ->json_is('/run/enterMs', 2000)->json_is('/run/exitMs', 2000);
$t->put_ok('/api/v1/cues/test' => json => {%$cue, line1 => 'Updated'})->status_is(200);
$t->get_ok('/api/v1/outputs/lower-third/state')->json_is('/run/cue/line1', $cue->{line1});
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'show', cueId => 'missing'})->status_is(404);
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'advance'})->status_is(400);
$t->post_ok('/api/v1/outputs/lower-third/commands' => {'Content-Type' => 'application/json'} => '[]')->status_is(400);
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'clear'})->status_is(200)->json_is('/phase', 'hidden');
$t->post_ok('/api/v1/cues' => json => {%$cue, id => 'alternate', theme => 'little-hills-directional'})->status_is(201);
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'show', cueId => 'alternate'})
    ->status_is(200)->json_is('/run/enterMs', 1200)->json_is('/run/exitMs', 1200);
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'clear'})->status_is(200);
$t->delete_ok('/api/v1/cues/alternate')->status_is(200);
$t->delete_ok('/api/v1/cues/test')->status_is(200);
$t->delete_ok('/api/v1/cues/test')->status_is(404);

# A new service loads saved cues but never resumes an on-air graphic.
$t->post_ok('/api/v1/cues' => json => $cue)->status_is(201);
$t->post_ok('/api/v1/outputs/lower-third/commands' => json => {action => 'show', cueId => 'test'})->status_is(200);
my $restarted = Test::Mojo->new(Mojo::Server->new->load_app("$FindBin::Bin/../script/display-server"));
$restarted->get_ok('/api/v1/cues')->status_is(200)->json_is('/3/id', 'test');
$restarted->get_ok('/api/v1/outputs/lower-third/state')->json_is('/phase', 'hidden');
done_testing;
