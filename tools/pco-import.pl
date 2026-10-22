#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use Getopt::Long qw(GetOptions);
use FindBin;
use lib "$FindBin::Bin/../lib";
use MdPresenter::Scripture qw(parseReference);

# FIXTURE ONLY. Doc-confirmed by the hub 1213 public API review (no live calls):
# https://api.planningcenteronline.com/docs/apps/services/versions/2018-11-01/vertices/item
# Item: item_type (song/header/media/item), integer sequence, title, description;
# relationships/include values: song, arrangement, item_notes.
# https://api.planningcenteronline.com/docs/apps/services/versions/2018-11-01/vertices/item_note
# ItemNote: content string.
# https://api.planningcenteronline.com/docs/apps/services/versions/2018-11-01/vertices/song
# Song: title.
# UNVERIFIED Song attributes: author, copyright, ccli_number. These optional
# fixture fields have not been confirmed by the public-docs review; absent
# values are omitted. No church licence number is read or emitted.
# https://api.planningcenteronline.com/docs/apps/services/versions/2018-11-01/vertices/arrangement
# Arrangement: lyrics string; sequence, sequence_short, sequence_full arrays.
# UNVERIFIED: lyrics section-label syntax and correspondence to sequence labels;
# the Verse/Chorus/Bridge convention below is a local fixture assumption.
# Availability of SongSelect-imported lyrics through the API is also unconfirmed.
# scripture_reference, translation and meta.plan.translation are not documented
# API fields and are ignored. Scripture titles are a local naming convention;
# translation comes only from --translation (default KJV).
# JSON:API data is an Item array with related resources in included. No links
# are followed, no credentials are read, and fetching is deliberately absent.
# Usage: perl tools/pco-import.pl --fixture plan.json [--output service.md] [--translation KJV]
# Without --output the complete service is written to stdout. Header items get
# // section plus a visible heading so that their notes survive generation.
# Media remains an explicit placeholder: no local paths are guessed.

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');
my ($fixture, $output, $help);
my $translation = 'KJV';
GetOptions('fixture=s' => \$fixture, 'output=s' => \$output, 'translation=s' => \$translation, 'help' => \$help)
    or die "Fixture-only importer: fetching is refused. Use --fixture local.json [--output service.md] [--translation KJV]\n";
if ($help) {
    print "Usage: perl tools/pco-import.pl --fixture local.json [--output service.md] [--translation KJV]\nLocal fixtures only; fetching is refused. No credentials are used.\n";
    exit 0;
}
die "Fixture-only importer: fetching is refused. Use --fixture local.json [--output service.md] [--translation KJV]\n"
    if @ARGV || !defined $fixture || $fixture =~ m{^[a-z][a-z0-9+.-]*:|^//}i;
$translation = moduleName($translation);
die "Fixture must be a local regular file\n" unless -f $fixture;
open my $fh, '<:raw', $fixture or die "Cannot read fixture: $!\n";
my $raw = do { local $/; <$fh> };
close $fh or die "Cannot close fixture: $!\n";
my $plan = eval { decode_json($raw) };
die "Malformed fixture: invalid JSON\n" if $@;
fail('root must be an object') unless ref($plan) eq 'HASH';
fail('data must be an array of Items') unless ref($plan->{data}) eq 'ARRAY';
my $included = $plan->{included} // [];
fail('included must be an array') unless ref($included) eq 'ARRAY';
my %resources;
for my $resource (@$included) {
    validateResource($resource);
    my $key = "$resource->{type}:$resource->{id}";
    fail('duplicate included resource') if exists $resources{$key};
    $resources{$key} = $resource;
}
my (@items, %ids, %positions);
for my $item (@{ $plan->{data} }) {
    validateResource($item);
    fail('data must contain Items') unless $item->{type} eq 'Item';
    fail('duplicate Item id') if $ids{$item->{id}}++;
    my $sequence = $item->{attributes}{sequence};
    fail('Item sequence must be a nonnegative integer')
        unless defined $sequence && !ref($sequence) && $sequence =~ /^\d+$/;
    fail('duplicate Item sequence') if $positions{0 + $sequence}++;
    push @items, $item;
}
my @blocks;
for my $item (sort { $a->{attributes}{sequence} <=> $b->{attributes}{sequence} } @items) {
    my $attrs = $item->{attributes};
    my $type = lc singleLine($attrs->{item_type}, 'Item item_type');
    my $title = singleLine($attrs->{title}, 'Item title');
    my @notes;
    push @notes, text($attrs->{description}, 'description') if defined $attrs->{description};
    for my $note (related($item, 'item_notes', 'ItemNote', 1)) {
        push @notes, text($note->{attributes}{content}, 'ItemNote content');
    }
    my @itemBlocks;
    my $isScripture = 0;
    if ($type eq 'header') {
        push @itemBlocks, '// section: ' . safeText($title) . "\n// insert: 0\n\n# " . safeText($title);
    } elsif ($type eq 'song') {
        my ($song) = related($item, 'song', 'Song', 0);
        my ($arrangement) = related($item, 'arrangement', 'Arrangement', 0);
        my $songTitle = $song ? singleLine($song->{attributes}{title}, 'Song title') : $title;
        if ($arrangement && defined $arrangement->{attributes}{lyrics}
                && $arrangement->{attributes}{lyrics} =~ /\S/) {
            @itemBlocks = songBlocks($songTitle, $arrangement->{attributes});
        } else {
            push @itemBlocks, placeholder($songTitle, 'Song has no local arrangement lyrics; add lyrics before presenting.');
        }
        $itemBlocks[0] = songDirective($songTitle, $song ? $song->{attributes} : {}) . "\n\n" . $itemBlocks[0];
    } elsif ($type eq 'media') {
        push @itemBlocks, placeholder($title, 'Media is not imported; add a local media file before presenting.');
    } elsif ($type eq 'item') {
        my $reference = scriptureReference($title);
        $isScripture = defined $reference;
        push @itemBlocks, defined $reference ? "!scripture $reference ($translation)" : '# ' . safeText($title);
    } else {
        push @itemBlocks, placeholder($title, "Unsupported item type '$type'; complete this item manually.");
    }
    @notes = grep { /\S/ } @notes;
    if (@notes) {
        my $notes = "Note:\n" . join("\n\n", map { safeText($_) } @notes) . "\n<!-- /notes -->";
        # Scripture expands before slide splitting. A closed notes block before
        # the directive stays with its first verse slide, not its last.
        $itemBlocks[0] = $isScripture ? "$notes\n\n$itemBlocks[0]" : "$itemBlocks[0]\n\n$notes";
    }
    push @blocks, @itemBlocks;
    push @blocks, '// songEnd' if $type eq 'song';
}
my $markdown = "// pcoWarning: Add the ccli deck directive with your actual licence number to enable song notices.\n\n"
    . join("\n\n---\n\n", @blocks) . "\n";
# Validate/render everything before opening an output file.
if (defined $output) {
    die "Output must be a local path\n" if $output =~ m{^[a-z][a-z0-9+.-]*:|^//}i;
    open my $out, '>:encoding(UTF-8)', $output or die "Cannot write output: $!\n";
    print {$out} $markdown or die "Cannot write output: $!\n";
    close $out or die "Cannot close output: $!\n";
} else {
    print $markdown or die "Cannot write stdout: $!\n";
}

sub fail {
    die "Malformed fixture: $_[0]\n";
}

sub text {
    my ($value, $field) = @_;
    fail("$field must be text") unless defined $value && !ref($value);
    $value =~ s/\r\n?/\n/g;
    return $value;
}

sub singleLine {
    my ($value, $field) = @_;
    $value = text($value, $field);
    fail("$field must be a nonempty single line") if $value !~ /\S/ || $value =~ /[\n\x00]/;
    return $value;
}

sub moduleName {
    my ($value) = @_;
    $value = singleLine($value, 'translation');
    fail('translation must be a SWORD module name') unless $value =~ /^[A-Za-z0-9_]+$/;
    return $value;
}

sub scriptureReference {
    my ($title) = @_;
    my $prefixed = $title =~ s/^Scripture:\s*//i;
    my $reference = eval { parseReference($title) };
    fail('invalid scripture reference in Item title') if $prefixed && !$reference;
    return $reference ? $reference->{display} : undef;
}

sub validateResource {
    my ($resource) = @_;
    fail('resource must be an object') unless ref($resource) eq 'HASH';
    singleLine($resource->{type}, 'resource type');
    singleLine($resource->{id}, 'resource id');
    fail('resource attributes must be an object') unless ref($resource->{attributes}) eq 'HASH';
    fail('relationships must be an object')
        if exists $resource->{relationships} && ref($resource->{relationships}) ne 'HASH';
}

sub related {
    my ($item, $name, $type, $many) = @_;
    my $relationship = ($item->{relationships} // {})->{$name};
    return () unless defined $relationship;
    fail("$name relationship must contain data") unless ref($relationship) eq 'HASH' && exists $relationship->{data};
    my $data = $relationship->{data};
    return () unless defined $data;
    fail("$name relationship must be " . ($many ? 'an array' : 'an object'))
        unless ref($data) eq ($many ? 'ARRAY' : 'HASH');
    my @targets = $many ? @$data : ($data);
    return map {
        fail("invalid $name relationship identifier") unless ref($_) eq 'HASH'
            && defined $_->{type} && !ref($_->{type}) && $_->{type} eq $type;
        my $id = singleLine($_->{id}, "$name relationship id");
        $resources{"$type:$id"} // fail("missing included $type resource");
    } @targets;
}

sub safeText {
    my ($value) = @_;
    # Expansion happens even inside notes. An invisible leading character
    # keeps imported prose from becoming presenter syntax. The generator
    # escapes HTML itself; entities here would be displayed literally.
    $value =~ s/^(\s*)(?=[!\/#*+\-<]|Notes?:|bg:)/$1 . "\x{200b}"/gme;
    return $value;
}

# Pipes delimit fields in // song, so use a visible fullwidth pipe in data.
# Replace source // with fullwidth slashes and neutralise other leading
# presenter syntax. Single-line validation prevents new directive injection.
sub songField {
    my ($value, $name) = @_;
    return '' unless defined $value;
    $value = text($value, $name);
    return '' unless $value =~ /\S/;
    $value = singleLine($value, $name);
    $value =~ s/\|/\x{ff5c}/g;
    $value =~ s{//}{\x{ff0f}\x{ff0f}}g;
    return safeText($value);
}

sub songDirective {
    my ($title, $attrs) = @_;
    my @fields = (songField($title, 'Song title'));
    push @fields, songField($attrs->{$_}, "Song $_") for qw(author copyright);
    my $number = songField($attrs->{ccli_number}, 'Song ccli_number');
    push @fields, length($number) ? 'CCLI Song # ' . $number : '';
    pop @fields while @fields && $fields[-1] eq '';
    return '// song: ' . join(' | ', @fields);
}

sub placeholder {
    my ($title, $warning) = @_;
    return '# ' . safeText($title) . "\n\n// pcoWarning: " . safeText($warning)
        . "\n\n[PCO import: manual completion required]";
}

sub sectionKey {
    my ($label) = @_;
    $label = lc $label;
    $label =~ s/\s+//g;
    return $label;
}

sub songBlocks {
    my ($title, $attrs) = @_;
    my $lyrics = text($attrs->{lyrics}, 'Arrangement lyrics');
    my (%sections, @order, @slides, $label);
    my $flush = sub {
        return unless @slides;
        my $key = defined $label ? sectionKey($label) : '__unlabelled';
        push @order, $key unless exists $sections{$key};
        push @{ $sections{$key} }, join("\n", @slides);
        @slides = ();
    };
    for my $line (split /\n/, $lyrics) {
        if ($line =~ /^\s*\[?((?:Verse(?:\s*\d+)?|Chorus(?:\s*\d+)?|Bridge(?:\s*\d+)?|Intro|Outro|Ending|Tag|Pre[- ]?Chorus(?:\s*\d+)?))\]?\s*:?\s*$/i) {
            $flush->();
            $label = $1;
        } elsif ($line !~ /\S/) {
            $flush->();
        } else {
            push @slides, $line;
        }
    }
    $flush->();
    fail('Arrangement lyrics contain no lyric slides') unless @order;
    my $sequence = $attrs->{sequence};
    if (defined $sequence) {
        fail('Arrangement sequence must be an array') unless ref($sequence) eq 'ARRAY';
        my @labels = @$sequence;
        if (@labels) {
            @order = map { sectionKey(singleLine($_, 'Arrangement sequence label')) } @labels;
            fail('Arrangement sequence names a missing lyric section') if grep { !exists $sections{$_} } @order;
            fail('Arrangement sequence cannot order unlabelled lyrics') if exists $sections{__unlabelled};
        }
    }
    return map { '# ' . safeText($title) . "\n\n" . safeText($_) }
        map { @{ $sections{$_} } } @order;
}
