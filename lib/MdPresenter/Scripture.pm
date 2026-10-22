package MdPresenter::Scripture;
use strict;
use warnings;
use utf8;
use Exporter 'import';
use File::Spec;

# Scripture references for the presenter.
#
#   !scripture John 3:16-18 (KJV)
#
# parseReference() turns the text after the directive into a checked reference.
# fetchVerses() asks the SWORD command-line tool diatheke for the verse text.
# versesToMarkdown() turns the verses into ordinary slide Markdown.

our @EXPORT_OK = qw(parseReference fetchVerses versesToMarkdown scriptureMarkdown findDiatheke);

our $defaultTranslation = 'KJV';
our $slideChars = 330;

# Canonical name, chapter count (KJV versification), extra abbreviations.
my @bookTable = (
    ['Genesis', 50, 'gen ge gn'],
    ['Exodus', 40, 'ex exo exod'],
    ['Leviticus', 27, 'lev le lv'],
    ['Numbers', 36, 'num nu nm nb'],
    ['Deuteronomy', 34, 'deut de dt'],
    ['Joshua', 24, 'josh jos jsh'],
    ['Judges', 21, 'judg jdg jg jdgs'],
    ['Ruth', 4, 'rth ru'],
    ['1 Samuel', 31, '1 sam 1 sa 1 sm 1 s'],
    ['2 Samuel', 24, '2 sam 2 sa 2 sm 2 s'],
    ['1 Kings', 22, '1 kgs 1 ki 1 kg'],
    ['2 Kings', 25, '2 kgs 2 ki 2 kg'],
    ['1 Chronicles', 29, '1 chr 1 chron 1 ch'],
    ['2 Chronicles', 36, '2 chr 2 chron 2 ch'],
    ['Ezra', 10, 'ezr'],
    ['Nehemiah', 13, 'neh ne'],
    ['Esther', 10, 'esth est es'],
    ['Job', 42, 'jb'],
    ['Psalms', 150, 'ps psa psalm pss psm'],
    ['Proverbs', 31, 'prov pro prv pr'],
    ['Ecclesiastes', 12, 'eccl ecc eccles qoh'],
    ['Song of Solomon', 8, 'song sos ss canticles cant'],
    ['Isaiah', 66, 'isa is'],
    ['Jeremiah', 52, 'jer je jr'],
    ['Lamentations', 5, 'lam la'],
    ['Ezekiel', 48, 'ezek eze ezk'],
    ['Daniel', 12, 'dan da dn'],
    ['Hosea', 14, 'hos ho'],
    ['Joel', 3, 'jl'],
    ['Amos', 9, 'am'],
    ['Obadiah', 1, 'obad ob'],
    ['Jonah', 4, 'jnh jon'],
    ['Micah', 7, 'mic mc'],
    ['Nahum', 3, 'nah na'],
    ['Habakkuk', 3, 'hab hb'],
    ['Zephaniah', 3, 'zeph zep zp'],
    ['Haggai', 2, 'hag hg'],
    ['Zechariah', 14, 'zech zec zc'],
    ['Malachi', 4, 'mal ml'],
    ['Matthew', 28, 'matt mt'],
    ['Mark', 16, 'mrk mk mr'],
    ['Luke', 24, 'luk lk'],
    ['John', 21, 'jn jhn joh'],
    ['Acts', 28, 'ac act'],
    ['Romans', 16, 'rom ro rm'],
    ['1 Corinthians', 16, '1 cor 1 co'],
    ['2 Corinthians', 13, '2 cor 2 co'],
    ['Galatians', 6, 'gal ga'],
    ['Ephesians', 6, 'eph ephes'],
    ['Philippians', 4, 'phil php pp'],
    ['Colossians', 4, 'col co'],
    ['1 Thessalonians', 5, '1 thess 1 thes 1 th'],
    ['2 Thessalonians', 3, '2 thess 2 thes 2 th'],
    ['1 Timothy', 6, '1 tim 1 ti 1 tm'],
    ['2 Timothy', 4, '2 tim 2 ti 2 tm'],
    ['Titus', 3, 'tit ti'],
    ['Philemon', 1, 'philem phm phlm'],
    ['Hebrews', 13, 'heb'],
    ['James', 5, 'jas jm'],
    ['1 Peter', 5, '1 pet 1 pe 1 pt 1 p'],
    ['2 Peter', 3, '2 pet 2 pe 2 pt 2 p'],
    ['1 John', 5, '1 jn 1 jhn 1 jo 1 j'],
    ['2 John', 1, '2 jn 2 jhn 2 jo 2 j'],
    ['3 John', 1, '3 jn 3 jhn 3 jo 3 j'],
    ['Jude', 1, 'jud jd'],
    ['Revelation', 22, 'rev re rv revelations'],
);

my (%bookByAlias, @bookList);
foreach my $row (@bookTable) {
    my ($name, $chapters, $aliases) = @$row;
    my $book = { name => $name, chapters => $chapters, key => normalizeBookName($name) };
    push @bookList, $book;
    $bookByAlias{ $book->{key} } = $book;
    # Aliases are listed space-separated; a numbered book's aliases come in
    # "1 xxx" pairs, so glue a leading digit back onto the word after it.
    my @words = split / /, $aliases;
    my @list;
    while (@words) {
        my $word = shift @words;
        if ($word =~ /^[123]$/ && @words) {
            $word .= ' ' . shift @words;
        }
        push @list, $word;
    }
    # Multi-word aliases without digits ("song of songs").
    push @list, 'song of songs', 'the revelation' if $name eq 'Song of Solomon' || $name eq 'Revelation';
    foreach my $alias (@list) {
        $bookByAlias{ normalizeBookName($alias) } ||= $book;
    }
}

sub normalizeBookName {
    my ($text) = @_;
    my $s = lc($text // '');
    $s =~ s/\.//g;
    $s =~ s/^\s+|\s+$//g;
    $s =~ s/\s+/ /g;
    $s =~ s/^(?:first|1st|i)\s+/1 /;
    $s =~ s/^(?:second|2nd|ii)\s+/2 /;
    $s =~ s/^(?:third|3rd|iii)\s+/3 /;
    $s =~ s/^([123])\s*(?=[a-z])/$1 /;
    return $s;
}

sub findBook {
    my ($text) = @_;
    my $key = normalizeBookName($text);
    die "Missing book name\n" unless length $key;
    return $bookByAlias{$key} if $bookByAlias{$key};

    # An unambiguous prefix of a full name ("Deuter", "Phile").
    my ($num, $rest) = $key =~ /^([123]) (.+)$/ ? ($1, $2) : ('', $key);
    my @hits = grep {
        my ($bnum, $brest) = $_->{key} =~ /^([123]) (.+)$/ ? ($1, $2) : ('', $_->{key});
        $bnum eq $num && length($rest) >= 2 && index($brest, $rest) == 0;
    } @bookList;
    return $hits[0] if @hits == 1;
    if (@hits > 1) {
        die "Book name \"$text\" is ambiguous (" . join(', ', map { $_->{name} } @hits) . ")\n";
    }
    die "Unknown book \"$text\"\n";
}

# Returns a hash:
#   book        canonical book name
#   translation SWORD module name
#   ranges      [ { startChapter, startVerse, endChapter, endVerse }, ... ]
#               (a missing verse means the whole chapter)
#   display     "John 3:16-18"
#   key         the same text, given to diatheke -k
sub parseReference {
    my ($text, %opt) = @_;
    my $source = $text // '';
    my $s = $source;
    $s =~ s/^\s+|\s+$//g;
    $s =~ s/[\x{2010}-\x{2015}\x{2212}]/-/g;

    my $translation = $opt{defaultTranslation} // $defaultTranslation;
    if ($s =~ s/\s*\(\s*([^()]*?)\s*\)\s*$//) {
        $translation = $1;
    }
    die "Bad translation \"$translation\" in \"$source\" (use a SWORD module name like KJV or WEB)\n"
        unless $translation =~ /^[A-Za-z0-9_]{1,32}$/;

    die "Cannot read the reference \"$source\" (expected e.g. John 3:16-18 (KJV))\n"
        unless $s =~ /^(.*?[A-Za-z].*?)\s*(\d[\d\s:,;\-]*)$/;
    my ($bookText, $spec) = ($1, $2);
    my $book = findBook($bookText);
    $spec =~ s/\s+//g;
    $spec =~ s/[,;]+$//;

    my $max = $book->{chapters};
    my $single = $max == 1;
    my @ranges;
    my $chapter;
    my $checkChapter = sub {
        my ($c) = @_;
        die "$book->{name} has no chapter $c (it has $max) in \"$source\"\n" if $c < 1 || $c > $max;
    };
    my $checkVerse = sub {
        my ($v) = @_;
        die "Verse 0 does not exist in \"$source\"\n" if $v < 1;
    };

    foreach my $group (split /;/, $spec) {
        undef $chapter;
        foreach my $seg (split /,/, $group) {
            next unless length $seg;
            my %r;
            if ($seg =~ /^(\d+):(\d+)-(\d+):(\d+)$/) {
                %r = (startChapter => $1, startVerse => $2, endChapter => $3, endVerse => $4);
            } elsif ($seg =~ /^(\d+):(\d+)-(\d+)$/) {
                %r = (startChapter => $1, startVerse => $2, endChapter => $1, endVerse => $3);
            } elsif ($seg =~ /^(\d+):(\d+)$/) {
                %r = (startChapter => $1, startVerse => $2, endChapter => $1, endVerse => $2);
            } elsif ($seg =~ /^(\d+)-(\d+)$/) {
                if (defined $chapter || $single) {
                    my $c = $chapter // 1;
                    %r = (startChapter => $c, startVerse => $1, endChapter => $c, endVerse => $2);
                } else {
                    %r = (startChapter => $1, endChapter => $2);
                }
            } elsif ($seg =~ /^(\d+)$/) {
                if (defined $chapter || $single) {
                    my $c = $chapter // 1;
                    %r = (startChapter => $c, startVerse => $1, endChapter => $c, endVerse => $1);
                } else {
                    %r = (startChapter => $1, endChapter => $1);
                }
            } else {
                die "Cannot read \"$seg\" in \"$source\"\n";
            }
            $r{$_} += 0 for grep { defined $r{$_} } keys %r;
            $checkChapter->($r{startChapter});
            $checkChapter->($r{endChapter});
            if (defined $r{startVerse}) {
                $checkVerse->($r{startVerse});
                $checkVerse->($r{endVerse});
                $chapter = $r{endChapter};
            }
            my $backwards = $r{endChapter} < $r{startChapter}
                || ($r{endChapter} == $r{startChapter} && defined $r{startVerse}
                    && $r{endVerse} < $r{startVerse});
            die "Range runs backwards in \"$source\"\n" if $backwards;
            push @ranges, \%r;
        }
    }
    die "No chapter or verse in \"$source\"\n" unless @ranges;

    (my $display = $spec) =~ s/,/, /g;
    $display =~ s/;/; /g;
    my $name = $book->{name};
    $name = 'Psalm' if $name eq 'Psalms' && $display =~ /^\d+(?::[\d\-,\s]+)?$/;
    return {
        book        => $book->{name},
        translation => $translation,
        ranges      => \@ranges,
        display     => "$name $display",
        key         => "$book->{name} $spec",
    };
}

sub findDiatheke {
    my (%opt) = @_;
    my $bin = $opt{diatheke} // $ENV{MDP_DIATHEKE};
    if (defined $bin && length $bin) {
        return -x $bin ? $bin : undef;
    }
    foreach my $dir (File::Spec->path) {
        my $candidate = File::Spec->catfile($dir, 'diatheke');
        return $candidate if -f $candidate && -x $candidate;
    }
    return undef;
}

# Returns [ { chapter, verse, text }, ... ] or dies with a reason a person can act on.
sub fetchVerses {
    my ($ref, %opt) = @_;
    my $bin = findDiatheke(%opt);
    unless ($bin) {
        die "!scripture $ref->{display} ($ref->{translation}) needs diatheke, the SWORD "
            . "command-line tool, and it is not installed here. Install it (Debian: "
            . "apt install diatheke, plus a module such as sword-text-kjv) or set "
            . "MDP_DIATHEKE to its path.\n";
    }
    my @cmd = ($bin, '-b', $ref->{translation}, '-f', 'plain', '-k', $ref->{key});
    my $pid = open(my $out, '-|');
    die "Cannot run diatheke: $!\n" unless defined $pid;
    if (!$pid) {
        open STDERR, '>&', \*STDOUT;
        exec { $cmd[0] } @cmd or do { print "exec failed: $!\n"; exit 127 };
    }
    binmode $out, ':encoding(UTF-8)';
    my @lines = <$out>;
    close $out;
    my $status = $? >> 8;
    my $raw = join '', @lines;
    die "diatheke failed (exit $status) for $ref->{display} ($ref->{translation}): "
        . firstLine($raw) . "\n" if $status;
    my $verses = parseDiathekePlain($raw);
    unless (@$verses) {
        die "diatheke returned no verses for $ref->{display} in module $ref->{translation}. "
            . "Is that module installed? (diatheke -b system -k modulelist) Output was: "
            . firstLine($raw) . "\n";
    }
    return $verses;
}

sub firstLine {
    my ($text) = @_;
    my ($line) = grep { /\S/ } split /\n/, ($text // '');
    return defined $line ? $line : '(nothing)';
}

# diatheke -f plain prints "John 3:16: For God so loved ..." per verse and
# the module name in parentheses at the end.
sub parseDiathekePlain {
    my ($raw) = @_;
    my @verses;
    foreach my $line (split /\n/, $raw // '') {
        $line =~ s/\s+$//;
        if ($line =~ /^(?:[123] )?[A-Za-z][A-Za-z ]*? (\d+):(\d+):\s?(.*)$/) {
            push @verses, { chapter => $1 + 0, verse => $2 + 0, text => $3 };
        } elsif ($line =~ /^\([A-Za-z0-9_]+\)$/) {
            next;
        } elsif (@verses && $line =~ /\S/) {
            $verses[-1]{text} .= ' ' . $line;
        }
    }
    foreach my $v (@verses) {
        $v->{text} =~ s/\x{b6}\s*//g;
        $v->{text} =~ s/\s+/ /g;
        $v->{text} =~ s/^\s+|\s+$//g;
    }
    return [ grep { length $_->{text} } @verses ];
}

sub superscript {
    my ($n) = @_;
    my %map = (0 => "\x{2070}", 1 => "\x{b9}", 2 => "\x{b2}", 3 => "\x{b3}",
        4 => "\x{2074}", 5 => "\x{2075}", 6 => "\x{2076}", 7 => "\x{2077}",
        8 => "\x{2078}", 9 => "\x{2079}");
    return join '', map { $map{$_} } split //, $n;
}

# Splits the verses into slides of about $slideChars characters, never
# splitting a verse. Returns Markdown with --- between the slides.
sub versesToMarkdown {
    my ($ref, $verses, %opt) = @_;
    my $budget = $opt{slideChars} // $slideChars;
    my @chunks;
    my $chunk = [];
    my $size = 0;
    foreach my $v (@$verses) {
        my $len = length $v->{text};
        if (@$chunk && $size + $len > $budget) {
            push @chunks, $chunk;
            $chunk = [];
            $size = 0;
        }
        push @$chunk, $v;
        $size += $len;
    }
    push @chunks, $chunk if @$chunk;

    my $name = $ref->{display};
    $name =~ s/\s+[\d:\-,;\s]+$//;
    my @slides;
    foreach my $c (@chunks) {
        my ($first, $last) = ($c->[0], $c->[-1]);
        my $label = "$name $first->{chapter}:$first->{verse}";
        if ($last->{chapter} != $first->{chapter}) {
            $label .= "-$last->{chapter}:$last->{verse}";
        } elsif ($last->{verse} != $first->{verse}) {
            $label .= "-$last->{verse}";
        }
        my $text = join ' ', map {
            my $t = $_->{text};
            superscript($_->{verse}) . $t;
        } @$c;
        push @slides, "## $label ($ref->{translation})\n\n$text\n";
    }
    return join "\n---\n\n", @slides;
}

sub scriptureMarkdown {
    my ($text, %opt) = @_;
    my $ref = parseReference($text, %opt);
    my $verses = fetchVerses($ref, %opt);
    return versesToMarkdown($ref, $verses, %opt);
}

1;
