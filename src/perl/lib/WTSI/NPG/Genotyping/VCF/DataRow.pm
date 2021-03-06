use utf8;

package WTSI::NPG::Genotyping::VCF::DataRow;

use Moose;
use WTSI::NPG::Genotyping::Call;
use WTSI::NPG::Genotyping::Types qw(:all);

with 'WTSI::DNAP::Utilities::Loggable';

has 'qscore'    =>
    (is       => 'ro',
     isa      => 'Maybe['.QualityScore.']',
     default  => undef,
     documentation => 'Phred quality score for alternate reference allele. Not to be confused with quality scores of the calls for each sample.'
 );

has 'filter'  =>
    (is       => 'ro',
     isa      => 'Str',
     default  => '.',
     documentation => 'Filter status; if missing, represent by "."');

has 'additional_info'  =>
    (is       => 'ro',
     isa      => 'Str',
     default  => '.',
     documentation => 'Miscellaneous information string for VCF output');

has 'calls'   =>
    (is       => 'ro',
     isa      => 'ArrayRef[WTSI::NPG::Genotyping::Call]',
     required => 1,
     documentation => 'Call objects to convert to VCF row format');

# attributes derived from the list of input Genotype::Call objects

has 'snp' =>
    (is       => 'ro',
     isa      => Variant,
     lazy     => 1,
     builder  => '_build_snp');

has 'vcf_chromosome_name' =>
    (is       => 'ro',
     isa      => 'Str',
     lazy     => 1,
     builder => '_build_vcf_chromosome_name',
     documentation => 'Chromosome name string; may be 1-22, X, Y');

has 'is_haploid' =>
    (is       => 'ro',
     isa      => 'Bool',
     builder  => '_build_haploid_status',
     lazy     => 1,
     documentation => 'Defaults to true for human X or Y chromosome,'.
                      'false otherwise. May be appropriate to override '.
                      'the default with an initarg, eg. for a diploid '.
                      'X variant.'
    );

# NB this class does not have the sample names; they are stored in VCF header

our $VERSION = '';

# genotype sub-fields GT = genotype; GQ = genotype quality; DP = read depth
our $GENOTYPE_FORMAT = 'GT:GQ:DP';
our $DEPTH_PLACEHOLDER = 1;
our $DEFAULT_QUALITY_STRING = '.';
our $NULL_ALLELE = 'N';

sub BUILD {
    my ($self, ) = @_;
    if (scalar @{$self->calls} == 0) {
        $self->logcroak("Must input at least one Call to create a VCF row");
    }
}

=head2 str

  Arg [1]    : None
  Example    : my $row_string = $data_row->str();
  Description: Return a string for output in the body of a VCF file.
  Returntype : Str

=cut

sub str {
    my ($self,)= @_;
    my @fields = ();
    my $alt;
    if ($self->is_haploid) { $alt = '.'; }
    else { $alt = $self->snp->alt_allele; }
    my $qscore;
    if (!defined($self->qscore)) { $qscore = '.'; }
    else {$qscore = $self->qscore; }
    push @fields, ($self->vcf_chromosome_name,
                   $self->snp->position,
                   $self->snp->name,
                   $self->snp->ref_allele,
                   $alt,
                   $qscore,
                   $self->filter,
                   $self->additional_info,
                   $GENOTYPE_FORMAT);
    foreach my $call (@{$self->calls}) {
        push @fields, $self->_call_to_vcf_field($call);
    }
    return join "\t", @fields;
}

sub _build_haploid_status {
    # Set haploid status to true or false
    # For now, the only haploid variants supported are human X or Y chromosome. X is diploid for human females and haploid for males, but the VCF specification does not support identical reference/alternate alleles, so for VCF output we treat the X marker as haploid.
    my ($self) = @_;
    if (is_XMarker($self->snp) || is_YMarker($self->snp)) { return 1; }
    else { return 0; }
}

sub _build_snp {
    # find SNP from input calls; check that SNP name is consistent
    my ($self) = @_;
    my $snp;
    foreach my $call (@{$self->calls}) {
        if (!defined($snp)) {
            $snp = $call->snp;
        } elsif ($call->snp->name ne $snp->name) {
            $self->logcroak("Inconsistent SNP names for input to ",
                            "VCF::DataRow: '", $snp->name, "', '",
                            $call->snp->name, "'");
        }
    }
    return $snp;
}

sub _build_vcf_chromosome_name {
    # find a vcf-compatible chromosome name string
    my ($self) = @_;
    my $chr = $self->snp->chromosome;
    if ($chr =~ m/^Chr/msx) {
        $chr =~ s/Chr//msx; # strip off 'Chr' prefix, if any
    }
    unless (is_HsapiensChromosome($chr)) {
        $self->logcroak("Unknown chromosome string: '",
                        $self->snp->chromosome, "'");
    }
    return $chr;
}

sub _call_to_vcf_field {
    # convert Call object to string of colon-separated sub-fields
    # sub-fields are genotype in VCF format, quality score, read depth
    my ($self, $call) = @_;
    if ($call->is_complement()) {
        # call is complemented with respect to the reference
        # complement it again, so it has the same orientation as reference
        $call = $call->complement();
    }
    my @alleles = split //msx, $call->genotype;
    my $allele_total;
    if ($self->is_haploid()) { $allele_total = 1; }
    else { $allele_total = 2; }
    my $i = 0;
    my @vcf_alleles;
    while ($i < $allele_total) {
        my $allele = $alleles[$i];
        if ($allele eq $self->snp->ref_allele) { push @vcf_alleles, '0'; }
        elsif ($allele eq $self->snp->alt_allele) { push @vcf_alleles, '1'; }
        elsif ($allele eq $NULL_ALLELE) { push @vcf_alleles, '.'; }
        else {
            $self->logcroak("Allele ", $allele, " does not match reference ",
                            $self->snp->ref_allele, " or alternate ",
                            $self->snp->alt_allele, " values for variant ",
                            $self->snp->name, ", genotype ", $call->genotype);
        }
        $i++;
    }
    my $vcf_call = join '/', @vcf_alleles;
    my $qscore;
    if (defined($call->qscore)) {
        if ($call->qscore == -1) {
            $qscore = $DEFAULT_QUALITY_STRING;
        } else {
            $qscore = $call->qscore;
        }
    } else {
        $qscore = $DEFAULT_QUALITY_STRING;
    }
    my @subfields = ($vcf_call, $qscore, $DEPTH_PLACEHOLDER);
    return join ':', @subfields;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=head1 NAME

WTSI::NPG::Genotyping::VCF::DataRow

=head1 DESCRIPTION

Class to represent one row in the main body of a VCF file. Contains
data for a particular variant (eg. a SNP or gender marker), including
genotype calls for one or more samples. General information on a VCF dataset,
including sample identifiers, is contained in a Header object.

=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (c) 2015 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
