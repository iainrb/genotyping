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

    my $results = $ssdb->find_studies_groups_for_sample($sample);

    my $group_ok = 0;

    foreach my $result (@{$results}) {
        my ($study, $group) = @{$result};
        if ($group ne 'None') { $group_ok = 1; }
        print "$path\t$sample\t$study\t$group\n";
    }

    unless ($group_ok) {
        print STDERR "$sample\n";
    }

}
