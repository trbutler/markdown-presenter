#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use FindBin;
use JSON::PP;
use lib "$FindBin::Bin/lib";
use MdPresenter::Expand qw(expandFile);
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

# FaithTree Presenter Generator
# Usage: perl generate.pl slides.md > presentation.html
# Or:    perl generate.pl slides.md presentation.html

my $input  = shift @ARGV or die "Usage: $0 <markdown-file> [output.html]\n";
my $output = shift @ARGV;

# !include and !scripture lines are expanded here, before the deck is split.
my @lineOrigins;
my $md = expandFile($input, lineOrigins => \@lineOrigins);
$md =~ s/\r\n/\n/g;
$md =~ s/\r/\n/g;

my $template_path = -f 'template.html' ? 'template.html' : "$FindBin::Bin/template.html";
open my $tfh, '<:utf8', $template_path or die "Cannot open $template_path: $!";
my $template = do { local $/; <$tfh> };
close $tfh;

my @blocks = parse_blocks($md, \@lineOrigins);
my $model  = build_model(@blocks);
my $html   = render($template, $model);

if ($output) {
    open my $out, '>:utf8', $output or die "Cannot write $output: $!";
    print $out $html;
    close $out;
    my $n = scalar @{ $model->{main} };
    my $f = scalar @{ $model->{fillers} };
    print STDERR "Wrote $output ($n slides, $f fillers)\n";
} else {
    print $html;
}

sub parse_blocks {
    my ($text, $origins) = @_;
    my @blocks;
    my $lineNo = 0;
    my @lines;
    foreach my $line (split /\n/, $text) {
        my $origin = $origins->[$lineNo++];
        if ($line =~ /^---\s*$/) {
            push @blocks, [@lines] if @lines;
            @lines = ();
        } else {
            push @lines, [ $line, $origin ];
        }
    }
    push @blocks, [@lines] if @lines;
    return @blocks;
}

sub parse_slide {
    my (@lines) = @_;
    my (%dir, %dirSource);
    my $song;
    my ($kicker, $title, $bg, $video) = ('', '', '', '');
    my (@bullets, @subtitle);
    my (@notes, $inNotes);

    foreach my $entry (@lines) {
        my ($line, $origin) = @$entry;
        # Speaker notes: "Note:" (or "Notes:") at the start of a line, or
        # <!-- notes -->, runs to the end of the slide or to <!-- /notes -->.
        if ($inNotes) {
            if ($line =~ /^\s*<!--\s*\/notes\s*-->\s*$/i) {
                $inNotes = 0;
            } else {
                push @notes, $line;
            }
            next;
        }
        if ($line =~ /^(?:Notes?:|<!--\s*notes\s*-->)\s*(.*?)\s*$/) {
            $inNotes = 1;
            push @notes, $1 if length $1;
            next;
        }
        if ($line =~ /^\s*\/\/\s*song(?:\s|:|$)/
                && $line !~ /^\s*\/\/\s*song(?:\s*:\s*.*?)?\s*$/) {
            warn join(':', @$origin) . ": Malformed // song: use Title | Authors | Copyright | CCLI Song # n\n";
            $dir{song} = undef;
            $song = undef;
            next;
        }
        if ($line =~ /^\s*\/\/\s*([A-Za-z][\w-]*)(?:\s*:\s*(.*?))?\s*$/) {
            my ($key, $value) = ($1, $2);
            $value =~ s/\s+$// if defined $value;
            $dir{$key} = $value;
            $dirSource{$key} = join(':', @$origin);
            $song = parseSong($value, $dirSource{$key}) if $key eq 'song';
        } elsif ($line =~ /^\s*bg:\s*(\S+)\s*$/ || $line =~ /^\s*!\[bg\]\((.+?)\)\s*$/) {
            $bg = $1;
        } elsif ($line =~ /^\s*##\s+(.+?)\s*$/) {
            $kicker = $1;
        } elsif ($line =~ /^\s*#\s+(.+?)\s*$/) {
            $title = $1;
        } elsif ($line =~ /^\s*[-*+]\s+(.+?)\s*$/) {
            push @bullets, $1;
        } elsif ($line =~ /\S/) {
            my $text = $line;
            $text =~ s/^\s+|\s+$//g;
            push @subtitle, $text;
        }
    }

    if (exists $dir{video}) {
        die "// video needs a file path\n" unless defined $dir{video} && length $dir{video};
        $video = $dir{video};
    }
    my $has = length($kicker) || length($title) || length($bg) || length($video)
        || @bullets || @subtitle;

    return {
        dir      => \%dir,
        dirSource => \%dirSource,
        song     => $song,
        kicker   => $kicker,
        title    => $title,
        subtitle => join("\n", @subtitle),
        bullets  => \@bullets,
        bg       => $bg,
        video    => $video // '',
        has      => $has ? 1 : 0,
        glued    => (defined $dir{position} && $dir{position} eq 'glued') ? 1 : 0,
        notes    => trimBlankLines(@notes),
    };
}

sub build_model {
    my (@raw_blocks) = @_;
    my %deck = (
        seed        => undef,
        autoAdvance => undef,
        loop        => JSON::PP::false,
        fadeMs      => 2000,
        audio       => undef,
    );
    my @sections;
    my @fillers;
    my $current;
    my $mode = 'main';
    my $seen_section = 0;
    my ($ccliLicense, $currentSong);
    my @songs;

    my $new_section = sub {
        my ($name) = @_;
        my $section = {
            name => $name // '', insert => 1, audio => undef, slides => [],
            countdown => undef, countdownLabel => undef, countdownEnd => undef, cycle => undef,
        };
        push @sections, $section;
        return $section;
    };

    foreach my $lines (@raw_blocks) {
        my $slide = parse_slide(@$lines);
        my $dir = $slide->{dir};

        foreach my $unknown (sort keys %$dir) {
            next if $unknown =~ /^(seed|autoAdvance|loop|fade|audio|type|section|insert|position|video|backdrop|name|title|buildIn|buildOut|translation|countdown|countdownEnd|cycle|ccli|song|songEnd)$/;
            warn "Unknown directive //$unknown\n";
        }

        if (exists $dir->{ccli}) {
            my $value = $dir->{ccli} // '';
            if ($value =~ /^\d+$/) {
                $ccliLicense = $value;
            } else {
                warn "$slide->{dirSource}{ccli}: // ccli needs a licence number; notices disabled\n";
                undef $ccliLicense;
            }
        }
        # A section, a new song, an explicit end or the filler pool ends the
        # previous song. Metadata-only song blocks attach to following slides.
        undef $currentSong if grep { exists $dir->{$_} } qw(section song songEnd type);
        if ($slide->{song}) {
            $currentSong = { fields => $slide->{song}, slides => [] };
            push @songs, $currentSong;
        }

        $deck{seed} = int($dir->{seed}) if exists $dir->{seed} && defined $dir->{seed} && $dir->{seed} =~ /^-?\d+$/;
        if (exists $dir->{seed} && defined $dir->{seed} && $dir->{seed} !~ /^-?\d+$/) {
            die "Bad seed: $dir->{seed}\n";
        }
        $deck{autoAdvance} = duration_ms($dir->{autoAdvance}) if exists $dir->{autoAdvance};
        $deck{loop} = boolish($dir->{loop}) ? JSON::PP::true : JSON::PP::false if exists $dir->{loop};
        $deck{fadeMs} = duration_ms($dir->{fade}) if exists $dir->{fade};

        if (exists $dir->{type} && defined $dir->{type} && $dir->{type} eq 'fillers') {
            $mode = 'filler';
        } elsif (exists $dir->{type}) {
            die "Unknown // type: " . ($dir->{type} // '') . "\n";
        }

        if ($mode eq 'filler') {
            warn "// section inside the filler pool is ignored\n" if exists $dir->{section};
            push @fillers, $slide if $slide->{has};
            next;
        }

        if (!$slide->{video} && grep { exists $dir->{$_} } qw(name title buildIn buildOut)) {
            warn "Lower third directives are only used on a video slide\n";
        }
        if (exists $dir->{backdrop}) {
            my $backdrop = $dir->{backdrop} // '';
            die "Bad backdrop: $backdrop\n" unless $backdrop eq 'blur';
            warn "Backdrop is only used on a video slide\n" unless $slide->{video};
        }

        if (exists $dir->{section}) {
            $seen_section = 1;
            my $name = defined $dir->{section} ? $dir->{section} : '';
            if (!$current || @{ $current->{slides} }) {
                $current = $new_section->($name);
            } else {
                $current->{name} = $name;
            }
        }

        if (exists $dir->{insert}) {
            my $n = $dir->{insert};
            die "Bad insert: " . ($n // '') . "\n" unless defined $n && $n =~ /^\d+$/;
            $current ||= $new_section->('');
            $current->{insert} = int($n);
        }

        # Announcement loops: // cycle: 8s keeps the section turning over
        # until the operator moves on. // countdown: 10:30 shows the time left
        # to that clock time; // countdownEnd: next leaves the section at zero.
        if (exists $dir->{cycle}) {
            $current ||= $new_section->('');
            $current->{cycle} = duration_ms($dir->{cycle});
        }
        if (exists $dir->{countdown}) {
            $current ||= $new_section->('');
            ($current->{countdown}, $current->{countdownLabel}) = countdownTime($dir->{countdown});
        }
        if (exists $dir->{countdownEnd}) {
            my $end = $dir->{countdownEnd} // '';
            die "Bad countdownEnd: $end (use stay or next)\n" unless $end =~ /^(stay|next)$/;
            $current ||= $new_section->('');
            $current->{countdownEnd} = $end;
        }

        if (exists $dir->{audio}) {
            my $audio = $dir->{audio};
            die "// audio needs a path or stop\n" unless defined $audio && length $audio;
            if (!$seen_section && !$current) {
                $deck{audio} = $audio;
            } else {
                $current ||= $new_section->('');
                $current->{audio} = $audio;
            }
        }

        if ($slide->{has}) {
            $current ||= $new_section->('');
            push @{ $current->{slides} }, $slide;
            push @{ $currentSong->{slides} }, $slide if $currentSong;
        }
    }

    if (defined $ccliLicense) {
        foreach my $song (@songs) {
            my $slides = $song->{slides};
            next unless @$slides;
            my $notice = join(' | ', @{ $song->{fields} }) . "\nCCLI License # $ccliLicense";
            $slides->[0]{ccliNotice} = $notice;
            $slides->[-1]{ccliNotice} = $notice;
        }
    }

    return {
        deck     => \%deck,
        sections => \@sections,
        main     => [ map { @{ $_->{slides} } } @sections ],
        fillers  => \@fillers,
    };
}

sub render {
    my ($template, $model) = @_;
    my @html;
    my $index = 0;
    foreach my $section (@{ $model->{sections} }) {
        foreach my $slide (@{ $section->{slides} }) {
            push @html, slide_html($slide, 'main', $index, $section->{name});
        }
        $index++;
    }
    push @html, slide_html($_, 'filler', '', '') for @{ $model->{fillers} };

    my @section_json = map {
        {
            name           => $_->{name},
            insert         => $_->{insert},
            audio          => $_->{audio},
            cycle          => $_->{cycle},
            countdown      => $_->{countdown},
            countdownLabel => $_->{countdownLabel},
            countdownEnd   => $_->{countdownEnd},
        }
    } @{ $model->{sections} };

    my $config = {
        seed        => $model->{deck}{seed},
        autoAdvance => $model->{deck}{autoAdvance},
        loop        => $model->{deck}{loop},
        fadeMs      => $model->{deck}{fadeMs},
        audio       => $model->{deck}{audio},
        sections    => \@section_json,
    };
    my $json = JSON::PP->new->ascii->canonical->encode($config);
    $json =~ s/</\\u003c/g;

    my $slides = join("\n", @html);
    $template =~ s/<!-- SLIDES_PLACEHOLDER -->/$slides/;
    $template =~ s|/\* DECK_CONFIG \*/|$json|;
    return $template;
}

sub slide_html {
    my ($slide, $deck_name, $section_index, $section_name) = @_;
    my $kind = length($slide->{video}) ? 'video' : 'slide';
    my @attrs = (
        'class="' . ($kind eq 'video' ? 'slide slide-video' : 'slide') . '"',
        'data-deck="' . esc($deck_name) . '"',
        'data-kind="' . $kind . '"',
    );
    push @attrs, 'data-section-index="' . esc($section_index) . '"' if $section_index ne '';
    push @attrs, 'data-section="' . esc($section_name) . '"' if defined $section_name && $section_name ne '';
    push @attrs, 'data-glued="1"' if $slide->{glued};

    if ($kind eq 'video') {
        my $src = esc($slide->{video});
        $src =~ s/ /%20/g;
        push @attrs, 'data-video="' . $src . '"';
        my $attr = join ' ', @attrs;
        my $lower = lower_third_html($slide) . ccliNoticeHtml($slide) . notesHtml($slide);
        my $blur = defined $slide->{dir}{backdrop} && $slide->{dir}{backdrop} eq 'blur';
        my $videos = $blur
            ? qq{    <canvas class="video-fill" aria-hidden="true"></canvas>\n}
              . qq{    <video class="video-fit" playsinline preload="none" src="$src"></video>\n}
            : qq{    <video playsinline preload="none" src="$src"></video>\n};
        return <<"HTML";
  <div $attr>
$videos$lower  </div>
HTML
    }

    my $bg = '';
    if (length $slide->{bg}) {
        $bg = '    <div class="slide-bg" style="background-image: url(\'' . esc($slide->{bg}) . '\')"></div>' . "\n";
    }
    my $kicker = '';
    if (length $slide->{kicker}) {
        $kicker = '    <div class="kicker">' . esc($slide->{kicker}) . "</div>\n";
    }
    my $title = '';
    if (length $slide->{title}) {
        $title = '      <h1>' . esc($slide->{title}) . "</h1>\n";
    }
    my $subtitle = '';
    if (length $slide->{subtitle}) {
        my $text = join('<br>', map { esc($_) } split /\n/, $slide->{subtitle});
        $subtitle = '      <p class="subtitle">' . $text . "</p>\n";
    }
    my $bullets = '';
    if (@{ $slide->{bullets} }) {
        $bullets = "      <ul>\n"
            . join('', map { '        <li>' . esc($_) . "</li>\n" } @{ $slide->{bullets} })
            . "      </ul>\n";
    }
    my $notes = ccliNoticeHtml($slide) . notesHtml($slide);
    my $attr = join ' ', @attrs;
    return <<"HTML";
  <div $attr>
$bg    <div class="gradient-top"></div>
    <div class="gradient-bottom"></div>
    <div class="bug">
      <img src="logo.png" alt="FaithTree" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
      <div class="fallback" style="display:none;">FT</div>
    </div>
$kicker    <div class="content">
$title$subtitle$bullets    </div>
$notes  </div>
HTML
}

# Up to four positional fields; empty optional fields are omitted, never
# supplied from defaults. A title is needed to identify the song.
sub parseSong {
    my ($value, $where) = @_;
    my @fields = split /\|/, ($value // ''), -1;
    s/^\s+|\s+$//g for @fields;
    if (!@fields || !length($fields[0]) || @fields > 4) {
        warn "$where: Malformed // song: use Title | Authors | Copyright | CCLI Song # n\n";
        return undef;
    }
    return [ grep { length } @fields ];
}

sub ccliNoticeHtml {
    my ($slide) = @_;
    return '' unless defined $slide->{ccliNotice};
    my $text = join('<br>', map { esc($_) } split /\n/, $slide->{ccliNotice});
    return qq{    <div class="ccli-notice" style="font-size: small;">$text</div>\n};
}

sub lower_third_html {
    my ($slide) = @_;
    my $dir = $slide->{dir};
    my $wanted = grep { exists $dir->{$_} } qw(name title buildIn buildOut);
    return '' unless $wanted;
    my $build_in  = exists $dir->{buildIn}  ? duration_ms($dir->{buildIn})  : 3000;
    my $build_out = exists $dir->{buildOut} ? duration_ms($dir->{buildOut}) : 8000;
    my $name  = exists $dir->{name}  ? esc($dir->{name}  // '') : '';
    my $title = exists $dir->{title} ? esc($dir->{title} // '') : '';
    return <<"HTML";
    <div class="lower-third" data-build-in="$build_in" data-build-out="$build_out">
      <div class="lt-window">
        <div class="lt-bar">
          <div class="lt-name">$name</div>
          <div class="lt-title">$title</div>
        </div>
      </div>
      <img class="lt-logo" src="logo.png" alt="">
    </div>
HTML
}

sub esc {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

sub duration_ms {
    my ($value) = @_;
    die "Missing duration\n" unless defined $value && $value ne '';
    return int($1) if $value =~ /^(\d+)\s*ms$/i;
    return int($1 * 1000) if $value =~ /^(\d+(?:\.\d+)?)\s*s$/i;
    return int($value) if $value =~ /^\d+$/;
    die "Bad duration: $value\n";
}

sub boolish {
    my ($value) = @_;
    return 1 if !defined $value || $value eq '';
    return 0 if $value =~ /^(0|false|no|off)$/i;
    return 1 if $value =~ /^(1|true|yes|on)$/i;
    die "Bad boolean: $value\n";
}

sub trimBlankLines {
    my (@lines) = @_;
    shift @lines while @lines && $lines[0] !~ /\S/;
    pop @lines while @lines && $lines[-1] !~ /\S/;
    return join("\n", @lines);
}

# Notes ride inside the slide and are never shown there; the notes view
# copies them into its own panel.
sub notesHtml {
    my ($slide) = @_;
    return '' unless defined $slide->{notes} && length $slide->{notes};
    my @paras = split /\n\s*\n/, $slide->{notes};
    my $body = join('', map {
        my $p = $_;
        $p =~ s/^\s+|\s+$//g;
        '      <p>' . join('<br>', map { esc($_) } split /\n/, $p) . "</p>\n";
    } @paras);
    return qq{    <aside class="notes" aria-hidden="true">\n$body    </aside>\n};
}

# "10:30", "10:30am", "7:05 PM", optionally followed by a label:
# "10:30 Worship begins in". Returns ("HH:MM", label or undef).
sub countdownTime {
    my ($value) = @_;
    die "// countdown needs a time like 10:30\n" unless defined $value && length $value;
    die "Bad countdown: $value\n"
        unless $value =~ /^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?(?:\s+(.*))?$/;
    my ($h, $m, $ampm, $label) = ($1, $2, $3, $4);
    if (defined $ampm) {
        die "Bad countdown: $value\n" if $h < 1 || $h > 12;
        $h = 0 if $h == 12;
        $h += 12 if lc($ampm) eq 'pm';
    }
    die "Bad countdown: $value\n" if $h > 23 || $m > 59;
    $label = undef if defined $label && $label !~ /\S/;
    return (sprintf('%02d:%02d', $h, $m), $label);
}
