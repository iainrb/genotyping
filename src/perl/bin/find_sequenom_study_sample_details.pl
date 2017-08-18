#!/software/bin/perl

use utf8;

package main;

use strict;
use warnings;

use Log::Log4perl qw(:levels);

use WTSI::DNAP::Utilities::ConfigureLogger qw(log_init);
use WTSI::NPG::Database::Warehouse;
use WTSI::NPG::iRODS;

# input: list of samples, iRODS paths

# for each path:
# - find study membership for sample
# - apply sample, study metadata to iRODS path
# - update permissions for study membership


my $log4perl_config = 'log4perl_tests.conf';
if (-f $log4perl_config) {
    my $session_log = 'tests.log';
    my @log_levels = ($DEBUG, );
    log_init(config => $log4perl_config,
             file   => $session_log,
             levels => \@log_levels);
}
my $config = $ENV{HOME} . "/.npg/genotyping.ini";
my $ssdb = WTSI::NPG::Database::Warehouse->new
    (name   => 'sequencescape_warehouse',
     inifile =>  $config)->connect(RaiseError           => 1,
                                   mysql_enable_utf8    => 1,
                                   mysql_auto_reconnect => 1);

my @input;
while (<STDIN>) {
    chomp;
    my @fields = split(/\s+/, $_);
    push @input, \@fields;
}

foreach my $pair (@input) {

    my ($sample, $path) = @{$pair};

    # query ssdb to get study/studies for each sample

    my $results = $ssdb->find_studies_identifiers_for_sample($sample);

    foreach my $result (@{$results}) {
        my ($sample_name, $sample_id, $study) = @{$result};
        print "$path\t$sample_name\t$sample_id\t$study\n";
    }

}
