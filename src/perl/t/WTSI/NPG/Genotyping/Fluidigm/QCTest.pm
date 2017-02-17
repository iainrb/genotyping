use utf8;

package WTSI::NPG::Genotyping::Fluidigm::QCTest;

use strict;
use warnings;

use base qw(WTSI::NPG::Test);
use File::Copy qw/copy/;
use File::Temp qw/tempdir/;
use Test::More tests => 4;
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

sub update : Test(2) {
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
    # Update the file with the other AssayDataObject and check the contents
    foreach my $irods_path (@irods_paths) {
        my $obj = WTSI::NPG::Genotyping::Fluidigm::AssayDataObject->new(
            $irods, $irods_path,
        );
        push @data_objects, $obj;
    }
    my $csv_path = "$tmp/$csv_name";
    my $qc = WTSI::NPG::Genotyping::Fluidigm::QC->new(csv_path => $csv_path);
    ok($qc->write_csv(\@data_objects) == 1, '1 object written');

    my $expected_csv = [
        [
            'ABC0123456789',
            '1.0000',
            96,
            96,
            70,
            70,
            96,
            26,
            26,
            '11413e77cde2a8dcca89705fe5b25a2d',
        ], [
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
    my $csv = Text::CSV->new ( { binary => 1 } );
    open my $fh, "<", $csv_path ||
        $log->logcroak("Cannot open CSV '$csv_path'");
    my $got_csv = $csv->getline_all($fh);
    close $fh || $log->logcroak("Cannot close CSV '$csv_path'");
    is_deeply($got_csv, $expected_csv, 'CSV contents match expected values');
}

1;
