
package WTSI::NPG::Genotyping::Fluidigm::QC;

use Moose;

use Set::Scalar;
use Text::CSV;

use WTSI::NPG::Genotyping::Fluidigm::AssayDataObject;
use WTSI::NPG::Genotyping::Fluidigm::AssayResultSet;

our $VERSION = '';

with 'WTSI::DNAP::Utilities::Loggable';

has 'csv_path' =>
  (is       => 'ro',
   isa      => 'Str',
   required => 1,
   documentation => 'Path for CSV input/output',
);


=head2 write_csv

  Arg [1]    : ArrayRef[WTSI::NPG::Genotyping::Fluidigm::AssayDataObject]

  Example    : $qc->write_csv($assay_data_objects);
  Description: Update the CSV file with the given AssayDataObjects.
               If the checksum of an AssayDataObject already appears in
               the CSV file, do nothing; otherwise, append a new line with
               the QC results and checksum.
  Returntype : [Int] Number of AssayDataObjects appended to file

=cut

sub write_csv {
    my ($self, $assay_data_objects) = @_;
    my $csv = Text::CSV->new ( { binary => 1 } );
    my $csv_checksums = $self->_find_checksums();
    open my $out, ">>", $self->csv_path ||
        $self->logcroak("Cannot open CSV '", $self->csv_path, "'");
    my $total_written = 0;
    foreach my $obj (@{$assay_data_objects}) {
        if ($csv_checksums->has($obj->checksum)) {
            $self->debug("Skipping data object ", $obj->str,
                         " as checksum is already present in CSV");
        } else {
            my @fields = @{$obj->assay_resultset->summary_fields};
            push @fields, $obj->checksum;
            $csv->combine(@fields);
            my $line = $csv->string;
            if (defined $line) {
                print $out $line."\n";
                $self->debug("Wrote QC for Fluidigm data object ", $obj->str);
                $total_written++;
            } else {
                $self->logwarn("Unable to combine input for CSV line: '",
                               $csv->error_input, "' from data object '",
                               $obj->str, "'");
            }
        }
    }
    close $out || $self->logcroak("Cannot close CSV '", $self->csv_path, "'");
    $self->debug("Wrote $total_written Fluidigm QC result(s)");
    return $total_written;
}


sub _find_checksums {
    # read the checksum column from the CSV file
    # class has no 'checksum' attribute
    # instead read checksums on the fly, so they should be up to date
    my ($self, ) = @_;
    my $checksums = Set::Scalar->new;
    if (-e $self->csv_path) {
        my $csv = Text::CSV->new ( { binary => 1 } );
        open my $fh, "<", $self->csv_path ||
            $self->logcroak("Cannot open CSV '", $self->csv_path, "'");
        while ( my $row = $csv->getline( $fh ) ) {
            my $checksum = $row->[-1];
            $checksums->insert($checksum);
        }
        close $fh ||
            $self->logcroak("Cannot close CSV '", $self->csv_path, "'");
    } else {
        $self->debug("CSV path '", $self->csv_path, "' does not exist; ",
                     "no checksums found for existing results");
    }
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

Appends metric values to a CSV file. Ensures QC values for the same data
object are not written more than once, by comparing md5 checksums.

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
