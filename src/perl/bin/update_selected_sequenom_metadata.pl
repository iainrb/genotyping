#!/software/bin/perl

use utf8;

package main;

use strict;
use warnings;

use Log::Log4perl qw(:levels);

use WTSI::DNAP::Utilities::ConfigureLogger qw(log_init);
use WTSI::NPG::iRODS;
use WTSI::NPG::iRODS::DataObject;
use WTSI::NPG::iRODS::Metadata;

# Tab-delimited input to supply AVUs:
# - iRODS path
# - other...


# AVUs to add:
# - study_id
# - sample = sample.name
# - sample_id = sample.internal_id

# grant read permission to group 'ss_{$STUDY_NAME}'

my $log4perl_config = 'update_selected_sequenom_metadata_log4perl.conf';
if (-f $log4perl_config) {
    my $session_log = 'update.log';
    my @log_levels = ($DEBUG, );
    log_init(config => $log4perl_config,
             file   => $session_log,
             levels => \@log_levels);
}
my $log = Log::Log4perl->get_logger('main');

my @input;
while (<STDIN>) {
    chomp;
    my @fields = split(/\s+/, $_);
    push @input, \@fields;
}


my $irods = WTSI::NPG::iRODS->new();

foreach my $item (@input) {

    my ($path, $sample_name, $sample_id, $study) = @{$item};

    my $obj = WTSI::NPG::iRODS::DataObject->new($irods, $path);

    $obj->add_avu($SAMPLE_NAME, $sample_name);
    $obj->add_avu($SAMPLE_ID, $sample_id);
    $obj->add_avu($STUDY_ID, $study);

    $log->info("Added AVU: ", $path, ' ', $SAMPLE_NAME, ' ', $sample_name);
    $log->info("Added AVU: ", $path, ' ', $SAMPLE_ID, ' ', $sample_id);
    $log->info("Added AVU: ", $path, ' ', $STUDY_ID, ' ', $study);

    my $group = 'ss_'.$study;
    $irods->set_object_permissions('read', $group, $path);

    $log->info("Added group read permission: ", $path, ' ', $group);

}
