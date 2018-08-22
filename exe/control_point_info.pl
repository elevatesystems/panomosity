#!/usr/bin/env perl

use strict;
use warnings;
use Panotools::Script;
use Getopt::Long qw(GetOptions);
use Data::Dumper;

my $pto_file;
my $control_point;
GetOptions(
  'input=s' => \$pto_file,
  'control_point=s' => \$control_point
) or die "Usage: $0 --input PTO_FILE --control_point CONTROL_POINT\n";

my $pano = new Panotools::Script;
$pano->Read ($pto_file);

for my $point (@{$pano->Control}) {
  print "@{[$point->Packed]} @{[$point->Distance($pano)]}\n";
}
