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
    $log->info("Updating QC results for ", @fluidigm_data_objects,
               " Fluidigm data objects");
    my %args;
    if (defined $old_csv) { $args{'csv_path'} = $old_csv; }
    my $qc = WTSI::NPG::Genotyping::Fluidigm::QC->new(\%args);
    my $updates = $qc->csv_update_strings();
    my $fh;
    if (defined $new_csv) {
        open $fh, ">>", $new_csv ||
            $log->logcroak("Cannot open output '", $new_csv, "'")
    } else {
        $fh = *STDOUT;
    }
    foreach my $update_string (@{$updates}) {
        print $fh $update_string."\n";
    }
    if (defined $new_csv) {
        close $fh || $log->logcroak("Cannot close output '", $new_csv, "'")
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
                 unless iRODS paths are supplied on STDIN.
  --verbose      Print messages while processing. Optional.

=head1 DESCRIPTION

Search for published Fluidigm genotyping data in iRODS; cross-reference
with existing QC results, if any; and append QC metrics for new data.

The CSV file for QC includes a field for the md5 checksum. If the checksum
for a Fluidigm result does not appear in the existing CSV file, QC metrics
for the result will be included in output. (If no existing CSV path is
given, the script will simply write QC metrics for all the input results.)

This script will read iRODS paths from STDIN as an alternative to
finding them via a metadata query. To do this, terminate the command
line with the '-' option. In this mode, the --query-path, --filter-key and
--filter-value options are invalid.

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
