#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
binmode STDOUT, ':utf8';

# FaithTree Presenter Generator
# Usage: perl generate.pl slides.md > presentation.html
# Or: perl generate.pl slides.md presentation.html

my $input  = shift @ARGV or die "Usage: $0 <markdown-file> [output.html]\n";
my $output = shift @ARGV;

open my $fh, '<:utf8', $input or die "Cannot open $input: $!";
my $md = do { local $/; <$fh> };
close $fh;

# Read template
my $template_path = 'template.html';
open my $tfh, '<:utf8', $template_path or die "Cannot open $template_path (run from the same directory): $!";
my $template = do { local $/; <$tfh> };
close $tfh;

# Split into slides on --- (with optional surrounding whitespace)
my @blocks = split /\n\s*---\s*\n/, $md;
my @slides_html;

for my $block (@blocks) {
    $block =~ s/^\s+|\s+$//g;
    next unless length $block;

    my $bg = '';
    my $title = '';
    my @bullets;

    # Extract bg: path or ![bg](path)
    if ($block =~ m{^(?:bg:\s*|\s*!\[bg\]\()(\S+?)\)?\s*$}m) {
        $bg = $1;
        $bg =~ s/^\s+|\s+$//g;
    }

    # Extract first # heading as title
    if ($block =~ m/^#\s+(.+)$/m) {
        $title = $1;
        $title =~ s/\s+$//;
    }

    # Extract bullet points (lines starting with - or * or +)
    while ($block =~ m/^\s*[-*+]\s+(.+)$/mg) {
        push @bullets, $1;
    }

    # Build slide HTML
    my $bg_style = $bg ? qq{ style="background-image: url('$bg');"} : '';
    my $bullets_html = '';
    if (@bullets) {
        $bullets_html = "<ul>\n" . join("\n", map { "      <li>$_</li>" } @bullets) . "\n    </ul>";
    }

    my $slide = <<"HTML";
  <div class="slide"$bg_style>
    <div class="gradient-top"></div>
    <div class="gradient-bottom"></div>
    <div class="bug">
      <img src="logo.png" alt="FaithTree" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
      <div class="fallback" style="display:none;">FT</div>
    </div>
    <div class="content">
      <h1>$title</h1>
      $bullets_html
    </div>
  </div>
HTML

    push @slides_html, $slide;
}

my $slides_block = join "\n", @slides_html;

$template =~ s/<!-- SLIDES_PLACEHOLDER -->/$slides_block/;

if ($output) {
    open my $out, '>:utf8', $output or die "Cannot write $output: $!";
    print $out $template;
    close $out;
    print STDERR "Wrote $output (" . scalar(@slides_html) . " slides)\n";
} else {
    print $template;
}
