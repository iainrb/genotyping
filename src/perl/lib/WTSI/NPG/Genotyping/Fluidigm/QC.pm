
package WTSI::NPG::Genotyping::Fluidigm::QC;

use Moose;

use Set::Scalar;
use Text::CSV;

use WTSI::NPG::iRODS::Metadata;
use WTSI::NPG::Genotyping::Fluidigm::AssayDataObject;
use WTSI::NPG::Genotyping::Fluidigm::AssayResultSet;

our $VERSION = '';

with 'WTSI::DNAP::Utilities::Loggable';

has 'csv_path' =>
  (is       => 'ro',
   isa      => 'Maybe[Str]',
   documentation => 'Path for input of existing QC results. If not '.
       'defined, omit CSV input.',
);

=head2 csv_update_fields

  Arg [1]    : ArrayRef[WTSI::NPG::Genotyping::Fluidigm::AssayDataObject]

  Example    : $qc->csv_update_fields($assay_data_objects);

  Description: Find updated QC data for the given AssayDataObjects.
               If the csv_path attribute is defined, and the checksum of an
               AssayDataObject is already present, do nothing; otherwise,
               append its CSV fields to the output.

               CSV format consists of the fields returned by the
               summary_string() method of
               WTSI::NPG::Genotyping::Fluidigm::AssayResultSet,
               with three extra fields appended.

               The extra fields denote the Fluidigm plate, Fluidigm well,
               and md5 checksum. The first two are derived from iRODS
               metadata, and may be an empty string if appropriate
               metadata is not present.

  Returntype : ArrayRef[ArrayRef] CSV fields for update

=cut

sub csv_update_fields {
    my ($self, $assay_data_objects) = @_;
    if (! defined $assay_data_objects || scalar @{$assay_data_objects} == 0) {
        $self->logwarn("Empty input to csv_update_fields");
    }
    my $csv_checksums;
    if (defined $self->csv_path) {
        $csv_checksums = $self->_read_checksums();
    }
    my @updates;
    foreach my $obj (@{$assay_data_objects}) {
        if (defined $csv_checksums && $csv_checksums->has($obj->checksum)) {
            $self->debug("Skipping data object ", $obj->str,
                         " as checksum is already present in CSV");
        } else {
            my @fields = @{$obj->assay_resultset->summary_fields};
            # Find Fluidigm plate/well (if any) from object metadata
            my ($plate, $well);
            my $plate_avu = $obj->get_avu($FLUIDIGM_PLATE_NAME);
            my $well_avu = $obj->get_avu($FLUIDIGM_PLATE_WELL);
            if ($plate_avu) {
                $plate = $plate_avu->{'value'};
            } else {
                $plate = '';
                $self->logwarn("$FLUIDIGM_PLATE_NAME AVU not found for data ",
                               "object '", $obj->str, "'");
            }
            if ($well_avu) {
                $well = $well_avu->{'value'};
            } else {
                $well = '';
                $self->logwarn("$FLUIDIGM_PLATE_WELL AVU not found for data ",
                               "object '", $obj->str, "'");
            }
            # Append plate, well, and md5 checksum
            push @fields, $plate, $well, $obj->checksum;
            $self->debug("Appending results for data object ",
                         $obj->str, " to output");
            push @updates, \@fields;
        }
    }
    $self->debug('Found ', scalar @updates, ' update(s) for Fluidigm QC');
    return \@updates;
}

=head2 csv_update_strings

  Arg [1]    : ArrayRef[WTSI::NPG::Genotyping::Fluidigm::AssayDataObject]

  Example    : $qc->csv_update_fields($assay_data_objects);
  Description: Find updated QC data for the given AssayDataObjects.
               Return strings for CSV output.
  Returntype : ArrayRef[Str]

=cut

sub csv_update_strings {
    my ($self, $assay_data_objects) = @_;
    my $updates = $self->csv_update_fields($assay_data_objects);
    my $csv = Text::CSV->new ( { binary => 1 } );
    my @update_strings;
    foreach my $fields (@{$updates}) {
        my $status = $csv->combine(@{$fields});
        if (! defined $status) {
            $self->logcroak("Error combining CSV inputs: '",
                            $csv->error_input, "'");
        }
        push @update_strings, $csv->string();
    }
    return \@update_strings;
}


sub _read_checksums {
    # read checksums from last column of a CSV file
    # class has no 'checksum' attribute
    # instead read checksums on the fly, so they should be up to date
    my ($self,) = @_;
    my $checksums = Set::Scalar->new;
    my $csv = Text::CSV->new ( { binary => 1 } );
    open my $fh, "<", $self->csv_path ||
        $self->logcroak("Cannot open CSV '", $self->csv_path, "'");
    while ( my $row = $csv->getline( $fh ) ) {
        my $checksum = $row->[-1];
        $checksums->insert($checksum);
    }
    close $fh ||
        $self->logcroak("Cannot close CSV '", $self->csv_path, "'");
    return $checksums;
}


__PACKAGE__->meta->make_immutable;

no Moose;

1;


__END__

=head1 NAME

WTSI::NPG::Genotyping::Fluidigm::QC

=head1 DESCRIPTION

A class to process quality control metrics for Fluidigm results.

Find QC metric values for CSV output. Ensure QC values for the
same data object are not written more than once, by comparing md5 checksums.

=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2017 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
