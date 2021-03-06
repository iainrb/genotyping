#! /software/bin/perl

use warnings;
use strict;
use Carp;
use Cwd;
use Getopt::Long;
use WTSI::NPG::Genotyping::QC::Identity;
use WTSI::NPG::Genotyping::QC::QCPlotShared qw(readThresholds);

our $VERSION = '';
our $DEFAULT_INI = $ENV{HOME} . "/.npg/genotyping.ini";

# Check identity of genotyped data against sequenom
# Input: files of genotypes in tab-delimited format, one row per SNP

# Author:  Iain Bancarz, ib5@sanger.ac.uk (refactored edition Feb 2012, original author unknown)

# Old version used heterozygosity mismatch rates for comparison
# Modify to use genotype mismatch rates
# Do not count "flips" and/or "swaps" as mismatches
# Flip:  Reverse complement, eg. GA and TC
# Swap:  Transpose major and minor alleles, eg. GA and AG
# can have both flip and swap, eg. GA ~ CT

# IMPORTANT:  Plink and Sequenom name formats may differ:
# - Plink *sample* names may be of the form PLATE_WELL_ID
#   where ID is the Sequenom identifier
# - Plink *snp* names may be of the form exm-FOO
#   where FOO is the Sequenom SNP name
# - Either of the above differences *may* occur, but is not guaranteed!

my ($outDir, $dbPath, $configPath, $iniPath, $minSNPs, $minIdent, $swap,
    $plink, $help);

# TODO introduce 'quiet' mode to suppress warnings

GetOptions("outdir=s"     => \$outDir,
	   "db=s"         => \$dbPath,
           "config=s"     => \$configPath,
           "ini=s"        => \$iniPath,
           "min_snps=i"   => \$minSNPs,
           "min_ident=f"  => \$minIdent,
	   "swap=f"       => \$swap,
	   "plink=s"      => \$plink,
           "h|help"       => \$help);

my $swapDefault = 0.95;

if ($help) {
    print STDERR "Usage: $0 [ output file options ] PLINK_GTFILE
PLINK_GTFILE is the prefix for binary plink files (without .bed, .bim, .fam extension)
Options:
--config=PATH       Config path in .json format with QC thresholds. 
                    At least one of config or min_ident must be given.
--ini=PATH          Path to .ini file with additional configuration. 
                    Defaults to: $DEFAULT_INI
--min_snps=NUMBER   Minimum number of SNPs for comparison
--min_ident=NUMBER  Minimum threshold of SNP matches for identity; if given, overrides value in config file; 0 <= NUMBER <= 1
--swap=NUMBER       Minimum threshold of SNP matches to flag a failed sample
                    pair as a potential swap; 0 <= NUMBER <= 1. Optional, 
                    defaults to $swapDefault.
--outdir=PATH       Directory for output files. Optional, defaults to current 
                    working directory.
--plink=PATH        Prefix for a Plink binary dataset, ie. path without .bed,
                    .bim, .fam extension. Required.
--db=PATH           Path to an SQLite pipeline database containing the QC plex calls. Required.
--help              Print this help text and exit
";
    exit(0);
}

$plink or die "Must supply a Plink binary input prefix\n";
foreach my $part (map { $plink . $_ } qw(.bed .bim .fam)) {
  -e $part or die "Prefix '$plink' is not a valid Plink binary dataset; " .
    "'$part' is missing\n";
}

if ($outDir) {
  -e $outDir or die "Output '$outDir' does not exist\n";
  -d $outDir or die "Output '$outDir' is not a directory\n";
}

$dbPath or die "Must supply an SQLite pipeline database path\n";
-e $dbPath or die "Database path '$dbPath' does not exist\n";

$outDir ||= getcwd();
$minSNPs ||= 8;
if (!$minIdent) {
    if ($configPath) {
        my %thresholds = readThresholds($configPath);
        $minIdent = $thresholds{'identity'};
    } else {
        die "Must supply a value for either --min_ident or --config\n";
    }
}
if ($minIdent < 0 || $minIdent > 1) {
    die "Minimum identity value must be a number between 0 and 1\n";
}
if ($swap && ($swap < 0 || $swap > 1)) {
    die "Swap threshold must be a number between 0 and 1\n";
}
$swap ||= $swapDefault;

$iniPath ||= $DEFAULT_INI;

WTSI::NPG::Genotyping::QC::Identity->new(
    db_path => $dbPath,
    ini_path => $iniPath,
    min_shared_snps => $minSNPs,
    output_dir => $outDir,
    pass_threshold => $minIdent,
    plink_path => $plink,
    swap_threshold => $swap
)->run_identity_check();
