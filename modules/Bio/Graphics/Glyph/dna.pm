package Bio::Graphics::Glyph::dna;

use strict;
use base qw(Bio::Graphics::Glyph::generic);

my %complement = (g=>'c',a=>'t',t=>'a',c=>'g',n=>'n',
		  G=>'C',A=>'T',T=>'A',C=>'G',N=>'N');

sub my_description {
    return <<END;
This glyph draws DNA sequences.  At high magnifications, this glyph
will draw the actual base pairs of the sequence (both strands).  At
low magnifications, the glyph will plot the GC content.  By default,
the GC calculation will use non-overlapping bins, but this can be
changed by specifying the gc_window option, in which case, a 
sliding window calculation will be used.

For this glyph to work, the attached feature must return 
a Bio::PrimarySeq DNA in response to the seq() method.
END
}

sub my_options {
    return {
	do_gc => [
	    'boolean',
	    1,
	    'Whether to draw the GC graph at low magnifications.'],
	gc_window=> [
	    'integer',
	    undef,
	    'Size of the sliding window to use in the GC content',
	    'calculation.  If this is not defined, non-overlapping',
	    'bins will be used. If this is set to "auto", then the',
	    'glyph will choose a window equal to 1% of the interval.'],
	gc_bins => [
	    'integer',
	    100,
	    'Fixed number of intervals to sample across the track.'],
	axis_color => [
	    'color',
	    'black',
	    'Color of the vertical axes in the GC content graph.'],
	strand => [
	    [qw(forward reverse both auto)],
	    'auto',
	    'Show both forward and reverse strand, one of "forward", "reverse",',
	    '"both" or "auto". In "auto" mode, +1 strand features will',
	    'show the plus strand, -1 strand features will',
	    'show the reverse complement and strandless features will show both.'],
    };
}

# turn off description
sub description { 0 }

# turn off label
# sub label { 1 }

sub pad_top {
    my $self = shift;
    my $font = $self->mono_font;
    my $pt   = $self->SUPER::pad_top;
    return $self->dna_fits 
	   ? $pt + $font->height+5
           : 16;
}

sub height {
  my $self = shift;
  my $font = $self->mono_font;
  return $self->dna_fits ? 2*$font->height
       : $self->do_gc    ? $self->SUPER::height
       : 0;
}

sub do_gc {
  my $self = shift;
  my $do_gc = $self->option('do_gc');
  return  if defined($do_gc) && !$do_gc;
  return  1;
}

sub draw_component {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = $self->bounds(@_);

  my $dna        = eval { $self->feature->seq };
  $dna           = $dna->seq if ref($dna) and $dna->can('seq'); # to catch Bio::PrimarySeqI objects
  $dna or return;

  # workaround for my misreading of interface -- LS
  $dna = $dna->seq if ref($dna) && $dna->can('seq');

  if ($self->dna_fits) {
    $self->draw_dna($gd,$dna,$x1,$y1,$x2,$y2);
  } elsif ($self->do_gc) {
    $self->draw_gc_content($gd,$dna,$x1,$y1,$x2,$y2);
  }
}

sub draw_dna {
  my $self = shift;

  my ($gd,$dna,$x1,$y1,$x2,$y2) = @_;
  my $pixels_per_base = $self->scale;
  my $feature = $self->feature;

  my $strand = $feature->strand || 1;
  $strand *= -1 if $self->{flip};

  my @bases = split '',$strand >= 0 ? $dna : $self->reversec($dna);

  my $color = $self->fgcolor;
  my $font  = $self->mono_font;
  my $lineheight = $font->height;
  $y1 -= $lineheight/2 - 3;
  my $strands = $self->option('strand') || 'auto';

  my ($forward,$reverse);
  if ($strands eq 'auto') {
    $forward = $feature->strand >= 0;
    $reverse = $feature->strand <= 0;
  } elsif ($strands eq 'both') {
    $forward = $reverse = 1;
  } elsif ($strands eq 'reverse') {
    $reverse = 1;
  } else {
    $forward = 1;
  }
  # minus strand features align right, not left
  $x1 += $pixels_per_base - $font->width - 1 if $strand < 0;
  for (my $i=0;$i<@bases;$i++) {
    my $x = $x1 + $i * $pixels_per_base;
    $gd->char($font,$x+2,$y1,$bases[$i],$color)                                   if $forward;
    $gd->char($font,$x+2,$y1+($forward ? $lineheight:0),
	      $complement{$bases[$i]}||$bases[$i],$color)                         if $reverse;
  }

}

sub draw_gc_content {
  my $self     = shift;
  my $gd       = shift;
  my $dna      = shift;
  my ($x1,$y1,$x2,$y2) = @_;

  $dna = $self->reversec($dna) if $self->{flip};
  my $font = $self->mono_font;

# get the options that tell us how to draw the GC content

  my $bin_size = length($dna) / ($self->option('gc_bins') || 100);
  $bin_size = 10 if $bin_size < 10;
  my $gc_window = $self->option('gc_window');
#  if ($gc_window && $gc_window eq 'auto' or $gc_window <= length($dna)) {
  if ($gc_window) {
    if ($gc_window eq 'auto') {
      $gc_window = length($dna)/100;
    } elsif ($gc_window > length($dna)) {
      $gc_window = length($dna);
    }
  }

# Calculate the GC content...

  my (@bins, @datapoints, $i);
  my $gc = 0;
  my $maxgc = -1000;
  my $mingc = +1000;

  if ($gc_window) { # ...using a sliding window...

    my @dna = split '', $dna;
    for ($i = 0; $i < @dna; $i++) {
      if ($dna[$i] eq 'G' or $dna[$i] eq 'C' or $dna[$i] eq 'g' or $dna[$i] eq 'c') {
	$dna[$i] = 1;
      } else {
	$dna[$i] = 0;
      }
    }

    for ($i = 0; $i < $gc_window; $i++) {$gc += $dna[$i]}

    push @datapoints, $gc;
    $datapoints[$#datapoints] > $maxgc and $maxgc = $datapoints[$#datapoints];
    $datapoints[$#datapoints] < $mingc and $mingc = $datapoints[$#datapoints];
    for ($i = 0; $i < @dna - $gc_window; $i++) {
      $gc -= $dna[$i];
      $gc += $dna[$i + $gc_window];
      push @datapoints, $gc;
      $datapoints[$#datapoints] > $maxgc and $maxgc = $datapoints[$#datapoints];
      $datapoints[$#datapoints] < $mingc and $mingc = $datapoints[$#datapoints];
    }

    my $scale = $maxgc - $mingc;
    $scale    = 1 unless $scale;
    for ($i = 0; $i < @datapoints; $i++) {
      $datapoints[$i] = ($datapoints[$i] - $mingc) / $scale;
    }
    $maxgc = int($maxgc * 100 / $gc_window);
    $mingc = int($mingc * 100 / $gc_window);

  } else { # ...or a fixed number of bins.

    for (my $i = 0; $i < length($dna) - $bin_size; $i+= $bin_size) {
      my $subseq  = substr($dna,$i,$bin_size);
      my $gc      = $subseq =~ tr/gcGC/gcGC/;
      my $content = $gc/$bin_size;
      $maxgc = $content if ($content > $maxgc);
      $mingc = $content if ($content < $mingc);
      push @bins,$content;
    }

    my $scale = $maxgc - $mingc;
    foreach (my $i; $i < @bins; $i++)
      {
	$bins[$i] = $scale != 0 ? ($bins[$i] - $mingc) / $scale : 0;
      }
    $maxgc = int($maxgc * 100);
    $mingc = int($mingc * 100);

  }

# Calculate values that will be used in the layout

  push @bins,0.5 unless @bins;  # avoid div by zero
  my $bin_width  = ($x2-$x1)/@bins;
  my $bin_height = $y2-$y1;
  my $fgcolor    = $self->fgcolor;
  my $bgcolor    = $self->factory->translate_color(
                      $self->option('grid color') || $self->panel->gridmajorcolor
                   );
  my $axiscolor  = $self->color('axis_color') || $fgcolor;

# Draw the axes
  my $fontwidth = $font->width;
  $gd->line($x1,  $y1,        $x1,  $y2,        $axiscolor);
  $gd->line($x2-2,$y1,        $x2-2,$y2,        $axiscolor);
  $gd->line($x1,  $y1,        $x1+3,$y1,        $axiscolor);
  $gd->line($x1,  $y2,        $x1+3,$y2,        $axiscolor);
  $gd->line($x1,  ($y2+$y1)/2,$x1+3,($y2+$y1)/2,$axiscolor);
  $gd->line($x2-4,$y1,        $x2-1, $y1,       $axiscolor);
  $gd->line($x2-4,$y2,        $x2-1, $y2,       $axiscolor);
  $gd->line($x2-4,($y2+$y1)/2,$x2-1,($y2+$y1)/2,$axiscolor);
  $gd->line($x1+5,$y2,        $x2-5,$y2,        $bgcolor);
  $gd->line($x1+5,($y2+$y1)/2,$x2-5,($y2+$y1)/2,$bgcolor);
  $gd->line($x1+5,$y1,        $x2-5,$y1,        $bgcolor);
  $gd->string($self->font,$x1-$self->string_width('% gc',$self->font),$y1,'% gc',$axiscolor) 
      if $bin_height > $self->font_height($font)*2;

# If we are using a sliding window, the GC graph will be scaled to use the full
# height of the glyph, so label the right vertical axis to show the scaling that# is in effect

  $gd->string($self->font,$x2+3,$y1,"${maxgc}%",$axiscolor) 
    if $bin_height > $self->font_height*2.5;
  $gd->string($self->font,$x2+3,$y2-$self->font_height,"${mingc}%",$axiscolor) 
    if $bin_height > $self->font_height*2.5;

# Draw the GC content graph itself

  if ($gc_window) {

    my $graphwidth = $x2 - $x1;

    # the $points_to_draw variable here can be used in various ways to adjust the
    # sampling of the graphic output. It could be converted to a glphy
    # option that can be set by user.  Here we are just using $graphwidth

#    my $points_to_draw = 1800;
    my $points_to_draw = $graphwidth;

    # if $points_to_draw is taken to mean the total number of points to show along the graph then
    my $inc = int (length($dna) / $points_to_draw) + 1;
    # it might be useful to set this to the x pixel resolution of your
    # screen or the "default width" option in the gbrowse config file or current pixel width

    # if $points_to_draw is taken to mean the number of points per $gc_window length then
#    my $inc = int ($gc_window / $points_to_draw) + 1;

    my $gc_window_width = $gc_window * $self->panel->scale; # pixels for the gc_window length
    my $scale = ($graphwidth - $gc_window_width) / @datapoints;
    for ($i = $inc; $i < @datapoints; $i += $inc) {
      my $x = $i + $gc_window / 2; # the base at the center of the gc_window
      my $xlo = $x1 + ($x - $inc) * $scale; # pixel coordinate for previous point
      my $xhi = $x1 + $x * $scale;
      $gd->line($xlo, $y2 - ($bin_height * $datapoints[$i-$inc]),
		$xhi, $y2 - ($bin_height * $datapoints[$i]),
		$fgcolor);
    }
  }
  else
  {
    for (my $i = 0; $i < @bins; $i++) 
      {
	  my $bin_start  = $x1+$i*$bin_width;
	  my $bin_stop   = $bin_start + $bin_width;
	  my $y          = $y2 - ($bin_height*$bins[$i]);
	  $gd->line($bin_start,$y,
		    $bin_stop,$y,
		    $fgcolor);
	  $gd->line($bin_stop,$y,
		    $bin_stop,$y2 - ($bin_height*$bins[$i+1]),
		    $fgcolor)
	      if $i < @bins-1;
      }
  }
}

sub make_key_feature {
  my $self = shift;
  my @gatc = qw(g a t c);
  my $offset = $self->panel->offset;
  my $scale = 1/$self->scale;  # base pairs/pixel

  my $start = $offset+1;
  my $stop  = $offset+100*$scale;
  my $feature =
    Bio::Graphics::Feature->new(-start=> $start,
				-stop => $stop,
				-seq  => join('',map{$gatc[rand 4]} (1..500)),
				-name => $self->option('key'),
				-strand => '+1',
			       );
  $feature;
}

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::dna - The "dna" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws DNA sequences.  At high magnifications, this glyph
will draw the actual base pairs of the sequence (both strands).  At
low magnifications, the glyph will plot the GC content.  By default,
the GC calculation will use non-overlapping bins, but this can be
changed by specifying the gc_window option, in which case, a 
sliding window calculation will be used.

For this glyph to work, the feature must return a Bio::PrimarySeq DNA
object in response to the seq() method. For example, you can use a
Bio::SeqFeature::Generic object with an attached Bio::PrimarySeq like
this:

  my $dna = Bio::PrimarySeq->new( -seq => 'A' x 1000 );
  my $feature = Bio::SeqFeature::Generic->new( -start => 1, -end => 800 );
  $feature->attach_seq($dna);
  $panel->add_track( $feature, -glyph => 'dna' );

A Bio::Graphics::Feature object may also be used.

=head2 OPTIONS

The following options are standard among all Glyphs.  See
L<Bio::Graphics::Glyph> for a full explanation.

  Option      Description                      Default
  ------      -----------                      -------

  -fgcolor      Foreground color	       black

  -outlinecolor	Synonym for -fgcolor

  -bgcolor      Background color               turquoise

  -fillcolor    Synonym for -bgcolor

  -linewidth    Line width                     1

  -height       Height of glyph		       10

  -font         Glyph font		       gdSmallFont

  -connector    Connector type                 0 (false)

  -connector_color
                Connector color                black

  -label        Whether to draw a label	       0 (false)

  -description  Whether to draw a description  0 (false)

  -hilite       Highlight color                undef (no color)

In addition to the common options, the following glyph-specific
options are recognized:

  Option      Description               Default
  ------      -----------               -------

  -do_gc      Whether to draw the GC      true
              graph at low mags

  -gc_window  Size of the sliding window  E<lt>noneE<gt>
  	      to use in the GC content 
	      calculation.  If this is 
	      not defined, non-
	      overlapping bins will be 
	      used. If this is set to
              "auto", then the glyph will
              choose a window equal to
              1% of the interval.

  -gc_bins    Fixed number of intervals   100
              to sample across the
              panel.

  -axis_color Color of the vertical axes  fgcolor
              in the GC content graph

  -strand      Show both forward and      auto
              reverse strand, one of
              "forward", "reverse",
              "both" or "auto".
              In "auto" mode,
              +1 strand features will
              show the plus strand
              -1 strand features will
              show the reverse complement
              and strandless features will
              show both

NOTE: -gc_window=E<gt>'auto' gives nice results and is recommended for
drawing GC content. The GC content axes draw slightly outside the
panel, so you may wish to add some extra padding on the right and
left.

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::cds>,
L<Bio::Graphics::Glyph::crossbox>,
L<Bio::Graphics::Glyph::diamond>,
L<Bio::Graphics::Glyph::dna>,
L<Bio::Graphics::Glyph::dot>,
L<Bio::Graphics::Glyph::ellipse>,
L<Bio::Graphics::Glyph::extending_arrow>,
L<Bio::Graphics::Glyph::generic>,
L<Bio::Graphics::Glyph::graded_segments>,
L<Bio::Graphics::Glyph::heterogeneous_segments>,
L<Bio::Graphics::Glyph::line>,
L<Bio::Graphics::Glyph::pinsertion>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::rndrect>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::ruler_arrow>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::translation>,
L<Bio::Graphics::Glyph::triangle>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Sliding window GC calculation added by Peter Ashton E<lt>pda@sanger.ac.ukE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
