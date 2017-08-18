#!/software/bin/perl

use utf8;

package main;

use strict;
use warnings;

use Log::Log4perl qw(:levels);

use WTSI::DNAP::Utilities::ConfigureLogger qw(log_init);
use WTSI::NPG::Genotyping::Database::Sequenom;

# Script to query for Sequenom plate names by samples
# Used to publish Sequenom plates for a list of older samples; see RT #586714
# Sample names on STDIN; plate names on STDOUT

my @samples;

while (<STDIN>) {
    chomp;
    push @samples, $_;
}

my $log4perl_config = 'log4perl_tests.conf';

if (-f $log4perl_config) {
    my $session_log = 'tests.log';
    my @log_levels = ($DEBUG, );
    log_init(config => $log4perl_config,
             file   => $session_log,
             levels => \@log_levels);
}

my $config = $ENV{HOME} . "/.npg/genotyping.ini";

my $sqdb = WTSI::NPG::Genotyping::Database::Sequenom->new
    (name    => 'mspec2',
     inifile => $config)->connect(RaiseError => 1);

my @plates = @{$sqdb->find_plates_from_sample_names(\@samples)};

foreach my $plate (@plates) {
    print "$plate\n";
}
