package MdPresenter::Expand;
use strict;
use warnings;
use utf8;
use Exporter 'import';
use Cwd qw(realpath);
use File::Basename qw(dirname);
use File::Spec;
use MdPresenter::Scripture ();

# Line directives that are handled before the deck is split into slides.
#
#   !include announcements.md      pastes that file in place of the line
#   !scripture John 3:16-18 (KJV)  pastes the verses as slides
#   // translation: WEB            default module for later !scripture lines
#
# An include path is relative to the file that names it, and it must stay
# inside the folder of the top-level deck: no absolute paths, no "..", and
# no symlink that resolves outside that folder.

our @EXPORT_OK = qw(expandFile resolveInclude);

our $maxDepth = 16;

# Optional lineOrigins receives [relative file, source line] per expanded
# line, including generated scripture lines, for downstream diagnostics.
sub expandFile {
    my ($path, %opt) = @_;
    my $fileReal = realpath($path);
    die "Cannot open $path: No such file\n" unless defined $fileReal && -f $fileReal;
    my $root = defined $opt{root} ? $opt{root} : dirname($fileReal);
    my $rootReal = realpath($root);
    die "Cannot resolve the deck folder $root\n" unless defined $rootReal && -d $rootReal;
    my %state = (
        root               => $rootReal,
        stack              => [],
        defaultTranslation => $opt{defaultTranslation},
        scripture          => $opt{scripture} || \&MdPresenter::Scripture::scriptureMarkdown,
        scriptureOpt       => $opt{scriptureOpt} || {},
    );
    my ($text, $origins) = expandAt($fileReal, \%state);
    @{ $opt{lineOrigins} } = @$origins if $opt{lineOrigins};
    return $text;
}

sub displayName {
    my ($real, $state) = @_;
    return File::Spec->abs2rel($real, $state->{root});
}

# $from is "file:line" of the !include that named this file, so cycle and
# depth errors point at the directive to change.
sub expandAt {
    my ($fileReal, $state, $from) = @_;
    my $stack = $state->{stack};
    my $where = defined $from ? "$from: " : '';
    if (grep { $_ eq $fileReal } @$stack) {
        my @chain = map { displayName($_, $state) } (@$stack, $fileReal);
        die $where . "Include cycle: " . join(' -> ', @chain) . "\n";
    }
    die $where . "Includes nested deeper than $maxDepth: " . displayName($fileReal, $state) . "\n"
        if @$stack >= $maxDepth;

    open my $fh, '<:encoding(UTF-8)', $fileReal or die "Cannot open " . displayName($fileReal, $state) . ": $!\n";
    my $text = do { local $/; <$fh> };
    close $fh;
    $text =~ s/\r\n?/\n/g;

    push @$stack, $fileReal;
    my $here = displayName($fileReal, $state);
    my (@out, @origins);
    my $lineNo = 0;
    foreach my $line (split /\n/, $text, -1) {
        $lineNo++;
        if ($line =~ /^\s*!include(?:\s+(.*?))?\s*$/) {
            my $spec = defined $1 ? $1 : '';
            my $target = eval { resolveInclude($spec, dirname($fileReal), $state->{root}) };
            die "$here:$lineNo: $@" if $@;
            my ($body, $bodyOrigins) = expandAt($target, $state, "$here:$lineNo");
            $body =~ s/\n+$//;
            push @out, $body;
            my $count = 1 + ($body =~ tr/\n/\n/);
            push @origins, map { $bodyOrigins->[$_] // [ $here, $lineNo ] } 0 .. $count - 1;
        } elsif ($line =~ /^\s*!scripture(?:\s+(.*?))?\s*$/) {
            my $ref = defined $1 ? $1 : '';
            die "$here:$lineNo: !scripture needs a reference, e.g. !scripture John 3:16-18 (KJV)\n"
                unless length $ref;
            my %sopt = (%{ $state->{scriptureOpt} });
            $sopt{defaultTranslation} = $state->{defaultTranslation} if defined $state->{defaultTranslation};
            my $md = eval { $state->{scripture}->($ref, %sopt) };
            die "$here:$lineNo: $@" if $@;
            $md =~ s/\n+$//;
            push @out, $md;
            my $count = 1 + ($md =~ tr/\n/\n/);
            push @origins, map { [ $here, $lineNo ] } 1 .. $count;
        } else {
            if ($line =~ /^\s*\/\/\s*translation\s*:\s*(\S+)\s*$/) {
                $state->{defaultTranslation} = $1;
            }
            push @out, $line;
            push @origins, [ $here, $lineNo ];
        }
    }
    pop @$stack;
    return (join("\n", @out), \@origins);
}

# Returns the real path of an include, or dies saying why it is refused.
sub resolveInclude {
    my ($spec, $baseDir, $rootReal) = @_;
    $spec = '' unless defined $spec;
    $spec =~ s/^\s+|\s+$//g;
    $spec = $1 if $spec =~ /^"(.*)"$/ || $spec =~ /^'(.*)'$/;
    die "!include needs a file name\n" unless length $spec;
    die "!include path must be relative to the deck: $spec\n"
        if $spec =~ m{^[/~]} || $spec =~ m{^[A-Za-z]:} || $spec =~ m{\\};
    die "!include path may not use ..: $spec\n"
        if grep { $_ eq '..' } split m{/+}, $spec;
    my $candidate = File::Spec->catfile($baseDir, $spec);
    die "!include file not found: $spec\n" unless -e $candidate;
    die "!include is not a file: $spec\n" unless -f $candidate;
    my $real = realpath($candidate);
    die "!include file not found: $spec\n" unless defined $real;
    die "!include leaves the deck folder: $spec\n"
        unless index($real, "$rootReal/") == 0;
    return $real;
}

1;
