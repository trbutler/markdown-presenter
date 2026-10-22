#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON::PP;
use Getopt::Long qw(GetOptions);

# FIXTURE ONLY. UNVERIFIED against the live Planning Center Services API:
# Item attributes item_type, sequence, title, description, scripture_reference,
# translation; relationships song, arrangement, notes; Song title;
# Arrangement lyrics (labelled plain text), sequence (array of labels or a
# comma-separated string); ItemNote content; meta.plan.translation.
# JSON:API data is an Item array with related resources in included. No links
# are followed, no credentials are read, and fetching is deliberately absent.
# Usage: perl tools/pco-import.pl --fixture plan.json [--output service.md]
# Without --output the complete service is written to stdout. Header items get
# // section plus a visible heading so that their notes survive generation.
# Announcements/media remain explicit placeholders: no local paths are guessed.

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');
my ($fixture, $output, $help);
GetOptions('fixture=s' => \$fixture, 'output=s' => \$output, 'help' => \$help)
    or die "Fixture-only importer: fetching is refused. Use --fixture local.json [--output service.md]\n";
if ($help) {
    print "Usage: perl tools/pco-import.pl --fixture local.json [--output service.md]\nLocal fixtures only; fetching is refused. No credentials are used.\n";
    exit 0;
}
die "Fixture-only importer: fetching is refused. Use --fixture local.json [--output service.md]\n"
    if @ARGV || !defined $fixture || $fixture =~ m{^[a-z][a-z0-9+.-]*:|^//}i;
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
my $defaultTranslation;
if (exists $plan->{meta}) {
    fail('meta must be an object') unless ref($plan->{meta}) eq 'HASH';
    if (exists $plan->{meta}{plan}) {
        fail('meta.plan must be an object') unless ref($plan->{meta}{plan}) eq 'HASH';
        $defaultTranslation = $plan->{meta}{plan}{translation};
    }
}
$defaultTranslation = moduleName($defaultTranslation) if defined $defaultTranslation;
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
    for my $note (related($item, 'notes', 'ItemNote', 1)) {
        push @notes, text($note->{attributes}{content}, 'ItemNote content');
    }
    my @itemBlocks;
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
    } elsif (($type eq 'item' || $type eq 'scripture')
            && (defined $attrs->{scripture_reference} || $title =~ /^Scripture:\s*(.+)$/i)) {
        my $reference = singleLine($attrs->{scripture_reference} // $1, 'scripture reference');
        fail('invalid scripture reference characters') unless $reference =~ /^[\p{L}\d\s:;,().-]+$/;
        my $translation = defined $attrs->{translation} ? moduleName($attrs->{translation}) : $defaultTranslation;
        push @itemBlocks, '!scripture ' . $reference . (defined $translation ? " ($translation)" : '');
    } elsif ($type eq 'item') {
        push @itemBlocks, '# ' . safeText($title);
    } else {
        push @itemBlocks, placeholder($title, "Unsupported item type '$type'; complete this item manually.");
    }
    @notes = grep { /\S/ } @notes;
    $itemBlocks[0] .= "\n\nNote:\n" . join("\n\n", map { safeText($_) } @notes) . "\n<!-- /notes -->" if @notes;
    push @blocks, @itemBlocks;
}
my $markdown = join("\n\n---\n\n", @blocks) . "\n";
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
        fail('Arrangement sequence must be an array or comma-separated text') if ref($sequence) && ref($sequence) ne 'ARRAY';
        my @labels = ref($sequence) ? @$sequence : split /\s*,\s*/, $sequence;
        if (@labels) {
            @order = map { sectionKey(singleLine($_, 'Arrangement sequence label')) } @labels;
            fail('Arrangement sequence names a missing lyric section') if grep { !exists $sections{$_} } @order;
            fail('Arrangement sequence cannot order unlabelled lyrics') if exists $sections{__unlabelled};
        }
    }
    return map { '# ' . safeText($title) . "\n\n" . safeText($_) }
        map { @{ $sections{$_} } } @order;
}
