#!/usr/bin/env perl

package main;

use strict;
use warnings;
use Getopt::Long;
use Log::Log4perl qw(:levels);
use Pod::Usage;
use Try::Tiny;

use WTSI::DNAP::Utilities::ConfigureLogger qw(log_init);
use WTSI::NPG::Genotyping::Fluidigm::AssayDataObject;
use WTSI::NPG::Genotyping::Fluidigm::QC;
use WTSI::NPG::iRODS;
use WTSI::NPG::Utilities qw(user_session_log);

my $uid = `whoami`;
chomp($uid);
my $session_log = user_session_log($uid, 'qc_fluidigm');

our $VERSION = '';

run() unless caller();

sub run {
    my $debug;
    my $in_place;
    my $log4perl_config;
    my $new_csv;
    my $old_csv;
    my $query_path;
    my $verbose;
    my @filter_key;
    my @filter_value;
    my $stdio;

    GetOptions('debug'          => \$debug,
               'filter-key=s'   => \@filter_key,
               'filter-value=s' => \@filter_value,
               'help'           => sub { pod2usage(-verbose => 2,
                                                   -exitval => 0) },
               'in-place'       => \$in_place,
               'logconf=s'      => \$log4perl_config,
               'new-csv=s'      => \$new_csv,
               'old-csv=s'      => \$old_csv,
               'query-path=s'   => \$query_path,
               'verbose'        => \$verbose,
               ''               => \$stdio); # Permits trailing '-' for STDIN

    # validate command line options and populate filter
    my @filter;
    if ($stdio) {
        if ($query_path or @filter_key) {
            pod2usage(-msg => "The --query-path and --filter-key options ".
                      "are incompatible with reading from STDIN\n",
                      -exitval => 2);
        }
    } else {
        if (! defined $query_path) {
             pod2usage(-msg => "If inputs are not supplied on STDIN, must ".
                       "specify --query-path\n",
                       -exitval => 2);
        }
        if (scalar @filter_key != scalar @filter_value) {
            pod2usage(-msg => "There must be equal numbers of filter keys " .
                          "and values\n",
                      -exitval => 2);
        }
        while (@filter_key) {
            push @filter, [pop @filter_key, pop @filter_value];
        }
    }
    if ($in_place) {
        if (defined $new_csv) {
            pod2usage(-msg => "The --new-csv and --in-place options ".
                          "are incompatible\n",
                      -exitval => 2);
        } elsif (! defined $old_csv) {
            pod2usage(-msg => "The --old-csv option is required for ".
                          "--in-place",
                      -exitval => 2);
        } else {
            $new_csv = $old_csv;
        }
    }
    # set up logging
    my @log_levels;
    if ($debug) { push @log_levels, $DEBUG; }
    if ($verbose) { push @log_levels, $INFO; }
    log_init(config => $log4perl_config,
             file   => $session_log,
             levels => \@log_levels);
    my $log = Log::Log4perl->get_logger('main');

    # Get input Fluidigm paths from STDIN or iRODS
    my $irods = WTSI::NPG::iRODS->new();
    my @fluidigm_data;
    if ($stdio) {
        while (my $line = <>) {
            chomp $line;
            push @fluidigm_data, $line;
        }
    } else {
        @fluidigm_data =
            $irods->find_objects_by_meta($query_path,
                                         [fluidigm_plate => '%', 'like'],
                                         [fluidigm_well  => '%', 'like'],
                                         [type           => 'csv'],
                                         @filter);
    }
    $log->info("Received ",  scalar @fluidigm_data,
               " Fluidigm data object paths");
    # Get Fluidigm data objects
    my @fluidigm_data_objects;
    foreach my $obj_path (@fluidigm_data) {
        try {
            my $fdo = WTSI::NPG::Genotyping::Fluidigm::AssayDataObject->new
                ($irods, $obj_path);
            push @fluidigm_data_objects, $fdo;

        } catch {
            $log->logcroak("Unable to create Fluidigm DataObject from ",
                           "iRODS path '", $obj_path, "'");
        };
    }
    # Write updated QC results
    my %args;
    if (defined $old_csv) { $args{'csv_path'} = $old_csv; }
    my $qc = WTSI::NPG::Genotyping::Fluidigm::QC->new(\%args);
    my $updates = $qc->csv_update_strings(\@fluidigm_data_objects);
    my $fh;
    if (defined $new_csv) {
        $log->debug("Appending output to path '$new_csv'");
        open $fh, ">>", $new_csv ||
            $log->logcroak("Cannot open output '", $new_csv, "'")
    } else {
        $log->debug("Writing output to STDOUT");
        $fh = *STDOUT;
    }
    foreach my $update_string (@{$updates}) {
        print $fh $update_string."\n";
    }
    if (defined $new_csv) {
        close $fh || $log->logcroak("Cannot close output '", $new_csv, "'");
    }
}

__END__

=head1 NAME

qc_fluidigm

=head1 SYNOPSIS

Options:

  --filter-key   Additional filter to limit set of dataObjs acted on.
  --filter-value
  --help         Display help.
  --in-place     If given, append QC results to the file specified by
                 --old-csv. Raises an error if --old-csv is not supplied.
                 Incompatible with --new-csv.
  --logconf      A log4perl configuration file. Optional.
  --new-csv      Path of a CSV file, to which new QC results will be
                 appended. Optional; if --new-csv and --in-place are not
                 given, output will be written to STDOUT.
  --old-csv      Path of a CSV file from which to read existing QC and
                 checksums. Any Fluidigm result whose md5 checksum appears
                 in the --old-csv file will be omitted from the output.
                 Optional; if not given, all QC results will be included
                 in output.
  --query-path   An iRODS path to query for Fluidigm DataObjects. Required,
                 unless iRODS paths are supplied on STDIN using the '-'
                 option.
  --verbose      Print messages while processing. Optional.

=head1 DESCRIPTION

Read published Fluidigm genotyping data from iRODS; cross-reference
with existing QC results, if any; and append QC metrics for new data in CSV
format.

=head2 Input

=head3 Fluidigm data

Input data from iRODS may be found via a metadata query, or from paths
given on STDIN:

=over

=item *

To query iRODS metadata, specify a search path using the --query-path option.
The default query is for data objects with 'fluidigm_plate' and
'fluidigm_well' attributes, and a 'type' attribute with value 'csv'.
Additional query keys and values may be specified with the --filter-key
and --filter-value options.

=item *

To read from STDIN, terminate the command line with the '-' option to read
from STDIN. In this mode, the --query-path, --filter-key and --filter-value
options are invalid.

=back

=head3 Existing QC results

If desired, specify existing QC results using the --old-csv option. If the
checksum for a Fluidigm result does I<not> appear in the existing CSV
file, QC metrics for the result will be included in output.

If no existing CSV path is given, the script will simply write CSV output
for all the input results.

=head2 Output

=head3 CSV fields

=over

=item 1. Sample identifier

=item 2. Call rate: Defined as field (8) / field (7), if field (7) is non-zero; zero otherwise.

=item 3. Total calls

=item 4. Total controls

=item 5. Total empty

=item 6. Total valid

=item 7. Total template assays: Defined as assays which are not empty and not controls.

=item 8. Total template calls: Defined as template assays in (7) which are calls.

=item 9. Fluidigm plate

=item 10. Fluidigm well

=item 11. md5 checksum

=back

Items 1 through 8 are taken from the fluidigm assay result file, while 9
through 11 are from iRODS metadata.

=head3 Output location

=over

=item * If the --in-place option is given, the script will append new results to the existing CSV file given by --old-csv.

=item * If the --new-csv option is supplied, the script will append to the given file.

=item * If neither option is given, results will be written to STDOUT.

=back


=head1 METHODS

None

=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (c) 2017 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
