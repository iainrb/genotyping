use utf8;

package WTSI::NPG::Genotyping::Fluidigm::QCTest;

use strict;
use warnings;

use base qw(WTSI::NPG::Test);
use File::Copy qw/copy/;
use File::Temp qw/tempdir/;
use Test::More tests => 6;
use Test::Exception;
use Text::CSV;

Log::Log4perl::init('./etc/log4perl_tests.conf');
our $log = Log::Log4perl->get_logger();

BEGIN { use_ok('WTSI::NPG::Genotyping::Fluidigm::QC'); }

use WTSI::NPG::Genotyping::Fluidigm::AssayDataObject;
use WTSI::NPG::Genotyping::Fluidigm::QC;
use WTSI::NPG::iRODS;
use WTSI::NPG::iRODS::Metadata; # has attribute name constants
use WTSI::NPG::Utilities qw(md5sum);

my $data_path = './t/fluidigm_qc/1381735059';
my $irods_tmp_coll;
my $pid = $$;
my $tmp;
my $csv_name = 'fluidigm_qc.csv';

sub make_fixture : Test(setup) {
    $tmp = tempdir('Fluidigm_QC_test_XXXXXX', CLEANUP => 1 );
    copy("./t/fluidigm_qc/$csv_name", $tmp);
    my $irods = WTSI::NPG::iRODS->new;
    $irods_tmp_coll = $irods->add_collection("FluidigmQCTest.$pid");
    $irods->put_collection($data_path, $irods_tmp_coll);
}

sub teardown : Test(teardown) {
    my $irods = WTSI::NPG::iRODS->new;
    $irods->remove_collection($irods_tmp_coll);
}

sub require : Test(1) {
    require_ok('WTSI::NPG::Genotyping::Fluidigm::AssayDataObject');
}

sub update : Test(4) {
    my $irods = WTSI::NPG::iRODS->new;
    my @irods_paths;
    my $barcode = '1381735059';
    foreach my $prefix (qw/S01 S02/) {
        my $data_file = $prefix.'_'.$barcode.'.csv';
        my $irods_path = "$irods_tmp_coll/$barcode/$data_file";
        push @irods_paths, $irods_path;
    }
    my @data_objects;
    # 1 of the 2 AssayDataObjects is already present in fluidigm_qc.csv
    # updated contents will contain QC results for the other AssayDataObject
    foreach my $irods_path (@irods_paths) {
        my $obj = WTSI::NPG::Genotyping::Fluidigm::AssayDataObject->new(
            $irods, $irods_path,
        );
        push @data_objects, $obj;
    }
    my $csv_path = "$tmp/$csv_name";
    my $qc = WTSI::NPG::Genotyping::Fluidigm::QC->new(csv_path => $csv_path);

    my $update_fields;
    lives_ok(sub {$update_fields = $qc->csv_update_fields(\@data_objects)},
             'Update fields found OK');
    my $expected_fields = [
        [
            'XYZ0987654321',
            '0.9231',
            96,
            94,
            70,
            70,
            96,
            26,
            24,
            '73ca301a0a9e1b9cf87d4daf59eb2815',
        ],
    ];
    is_deeply($update_fields, $expected_fields,
              'Update field contents match expected values');

    my $update_strings;
    lives_ok(sub {$update_strings = $qc->csv_update_strings(\@data_objects)},
             'Update strings found OK');
    my $expected_string = 'XYZ0987654321,0.9231,96,94,70,70,96,26,24,'.
        '73ca301a0a9e1b9cf87d4daf59eb2815';
    my $expected_strings = [ $expected_string, ];
    is_deeply($update_strings, $expected_strings,
              'Update string contents match expected values');

}

1;
