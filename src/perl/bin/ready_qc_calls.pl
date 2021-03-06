#!/software/bin/perl

use utf8;

package main;

use warnings;
use strict;
use Config::IniFiles;
use File::Slurp qw(read_file);
use Getopt::Long;
use JSON;
use List::AllUtils qw(uniq);
use Log::Log4perl;
use Log::Log4perl::Level;
use Pod::Usage;
use Try::Tiny;

use WTSI::NPG::Genotyping::Database::Pipeline;
use WTSI::NPG::Genotyping::VCF::PlexResultFinder;
use WTSI::NPG::Utilities qw(user_session_log);

our $VERSION = '';

our $DEFAULT_INI = $ENV{HOME} . "/.npg/genotyping.ini";
our $SEQUENOM = 'sequenom';
our $FLUIDIGM = 'fluidigm';
our $DEFAULT_DATA_PATH = '/seq/fluidigm';
our $CALLSET_NAME_KEY = 'callset_name';

# keys for config hash
our $IRODS_DATA_PATH_KEY      = 'irods_data_path';
our $PLATFORM_KEY             = 'platform';
our $REFERENCE_NAME_KEY       = 'reference_name';
our $REFERENCE_PATH_KEY       = 'reference_path';
our $SNPSET_NAME_KEY          = 'snpset_name';
our $READ_VERSION_KEY         = 'read_snpset_version';
our $WRITE_VERSION_KEY        = 'write_snpset_version';
our @REQUIRED_CONFIG_KEYS = ($IRODS_DATA_PATH_KEY,
                             $PLATFORM_KEY,
                             $REFERENCE_NAME_KEY,
                             $REFERENCE_PATH_KEY,
                             $SNPSET_NAME_KEY);
my $uid = `whoami`;
chomp($uid);
my $session_log = user_session_log($uid, 'ready_qc_calls');

my $embedded_conf = "
   log4perl.logger.npg.ready_qc_calls = ERROR, A1, A2

   log4perl.appender.A1           = Log::Log4perl::Appender::Screen
   log4perl.appender.A1.utf8      = 1
   log4perl.appender.A1.layout    = Log::Log4perl::Layout::PatternLayout
   log4perl.appender.A1.layout.ConversionPattern = %d %p %m %n

   log4perl.appender.A2           = Log::Log4perl::Appender::File
   log4perl.appender.A2.filename  = $session_log
   log4perl.appender.A2.utf8      = 1
   log4perl.appender.A2.layout    = Log::Log4perl::Layout::PatternLayout
   log4perl.appender.A2.layout.ConversionPattern = %d %p %m %n
   log4perl.appender.A2.syswrite  = 1
";

my $log;

run() unless caller();

sub run {
    my $callset;
    my $config;
    my $dbfile;
    my $debug;
    my $inifile;
    my $log4perl_config;
    my $manifest_dir;
    my $output_dir;
    my $verbose;

    GetOptions('callset=s'        => \$callset,
               'config=s'         => \$config,
               'dbfile=s'         => \$dbfile,
               'debug'            => \$debug,
               'help'             => sub { pod2usage(-verbose => 2,
                                                     -exitval => 0) },
               'inifile=s'        => \$inifile,
               'logconf=s'        => \$log4perl_config,
               'manifest_dir=s'   => \$manifest_dir,
               'out=s'            => \$output_dir,
               'verbose'          => \$verbose);

    $inifile ||= $DEFAULT_INI;

    ### set up logging ###
    if ($log4perl_config) {
        Log::Log4perl::init($log4perl_config);
        $log = Log::Log4perl->get_logger('npg.vcf.qc');
    }
    else {
        Log::Log4perl::init(\$embedded_conf);
        $log = Log::Log4perl->get_logger('npg.vcf.qc');
        if ($verbose) {
            $log->level($INFO);
        }
        elsif ($debug) {
            $log->level($DEBUG);
        }
    }

    ### validate command-line arguments ###
    my @config = split(/,/msx, $config);
    # JSON config files supplied as a comma-separated list
    # Use instead of eg. "--config foo.json --config bar.json" for
    # compatibility with Percolate cli_args_map function
    if (scalar @config == 0) {
        $log->logcroak("Must supply at least one --config argument");
    }
    foreach my $config_path (@config) {
        unless (-e $config_path) {
            $log->logcroak("Config path '", $config_path,
                           "' does not exist. Paths must be supplied as ",
                           "a comma-separated list; individual paths ",
                           "cannot contain commas.");
        }
    }
    if (!(defined($output_dir))) {
        $log->logcroak("--out argument is required");
    } elsif (!(-d $output_dir)) {
        $log->logcroak("--out argument '", $output_dir,
                       "' is not a directory");
    }
    if (defined($manifest_dir) && !(-d $manifest_dir)) {
        $log->logcroak("--manifest_dir argument '", $manifest_dir,
                       "' is not a directory");
    }
    $manifest_dir ||= $output_dir;

    if (!$dbfile) {
        $log->logcroak("--dbfile argument is required");
    } elsif (! -e $dbfile) {
        $log->logcroak("--dbfile argument '", $dbfile, "' does not exist");
    }

    ### read sample identifiers from pipeline DB ###
    my @initargs = (name        => 'pipeline',
                    inifile     => $inifile,
                    dbfile      => $dbfile);
    my $pipedb = WTSI::NPG::Genotyping::Database::Pipeline->new
        (@initargs)->connect
            (RaiseError     => 1,
             sqlite_unicode => 1,
             on_connect_do  => 'PRAGMA foreign_keys = ON');
    my @samples = $pipedb->sample->all;
    my @sample_ids = uniq map { $_->sanger_sample_id } @samples;

    ### create PlexResultFinder and write VCF ###
    try {
        my $finder = WTSI::NPG::Genotyping::VCF::PlexResultFinder->new(
            sample_ids => \@sample_ids,
            subscriber_config => \@config,
            logger     => $log,
        );
        my $plex_manifests = $finder->write_manifests($manifest_dir);
        $log->info("Wrote plex manifests: ", join(', ', @{$plex_manifests}));
        my $vcf_paths = $finder->write_vcf($output_dir);
        $log->info("Wrote VCF: ", join(', ', @{$vcf_paths}));
    } catch {
         $log->logwarn("Unexpected error finding QC plex data in ",
                       "iRODS; run with --verbose for details");
         $log->info("Caught PlexResultFinder error: $_");
    }
}


__END__

=head1 NAME

ready_qc_calls

=head1 SYNOPSIS

ready_qc_calls --dbfile <path to SQLite DB>  --out <output directory>

Options:

  --callset        Callset name to record in VCF header. Used for grouping
                   calls (eg. from different platforms or runs) in identity
                   check output. Optional, defaults to platform name in
                   file supplied for --config.
  --config         Comma-separated list of paths to one or more JSON files,
                   with configuration parameters for reading the QC plex
                   calls. The individual paths *cannot* contain commas.
                   Required.
  --dbfile         Path to pipeline SQLite database file. Used to read
                   sample identifiers. Required.
  --help           Display help.
  --inifile        Path to .ini file to configure pipeline SQLite database
                   connection. Optional. Only relevant if --dbfile is given.
  --manifest_dir   Directory for output of QC plex manifests retrieved from
                   iRODS. Optional, defaults to the --out argument.
  --out            Directory for VCF output. Required.


=head1 DESCRIPTION

Read sample names from a pipeline SQLite database file; retrieve QC plex
calls and metadata from iRODS; and write to a VCF file for use by the
pipeline identity check.

=head1 METHODS

None

=head1 AUTHOR

Iain Bancarz <ib5@sanger.ac.uk>

=head1 COPYRIGHT AND DISCLAIMER

Copyright (C) 2015, 2016 Genome Research Limited. All Rights Reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
