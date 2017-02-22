use utf8;

package WTSI::NPG::Genotyping::Fluidigm::QCTest;

use strict;
use warnings;

use base qw(WTSI::NPG::Test);
use File::Copy qw/copy/;
use File::Temp qw/tempdir/;
use Test::More tests => 10;
use Test::Exception;
use Text::CSV;

our $logconf = './etc/log4perl_tests.conf';
Log::Log4perl::init($logconf);
our $log = Log::Log4perl->get_logger();

BEGIN { use_ok('WTSI::NPG::Genotyping::Fluidigm::QC'); }

use WTSI::NPG::Genotyping::Fluidigm::AssayDataObject;
use WTSI::NPG::Genotyping::Fluidigm::QC;
use WTSI::NPG::iRODS;
use WTSI::NPG::iRODS::Metadata; # has attribute name constants
use WTSI::NPG::Utilities qw(md5sum);

my $script = 'qc_fluidigm.pl';
my $plate = '1381735059';
my $data_path = "./t/fluidigm_qc/$plate";
my $irods_tmp_coll;
my @irods_paths;
my $pid = $$;
my $tmp;
my $csv_name = 'fluidigm_qc.csv';

sub make_fixture : Test(setup) {
    $tmp = tempdir('Fluidigm_QC_test_XXXXXX', CLEANUP => 1 );
    copy("./t/fluidigm_qc/$csv_name", $tmp);
    my $irods = WTSI::NPG::iRODS->new;
    $irods_tmp_coll = $irods->add_collection("FluidigmQCTest.$pid");
    $irods->put_collection($data_path, $irods_tmp_coll);
    my %wells = (
        'S01_1381735059.csv' => 'S01',
        'S02_1381735059.csv' => 'S02',
    );
    foreach my $name (keys %wells) {
        my $irods_path = $irods_tmp_coll.'/'.$plate.'/'.$name;
        $irods->add_object_avu($irods_path, 'type', 'csv');
        $irods->add_object_avu($irods_path, 'fluidigm_plate', $plate);
        $irods->add_object_avu($irods_path, 'fluidigm_well', $wells{$name});
        push @irods_paths, $irods_path;
    }
}

sub teardown : Test(teardown) {
    @irods_paths = ();
    my $irods = WTSI::NPG::iRODS->new;
    $irods->remove_collection($irods_tmp_coll);
}

sub require : Test(1) {
    require_ok('WTSI::NPG::Genotyping::Fluidigm::AssayDataObject');
}

sub update : Test(4) {
    my $irods = WTSI::NPG::iRODS->new;
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
            '1381735059',
            'S02',
            '73ca301a0a9e1b9cf87d4daf59eb2815',
        ],
    ];
    is_deeply($update_fields, $expected_fields,
              'Update field contents match expected values');

    my $update_strings;
    lives_ok(sub {$update_strings = $qc->csv_update_strings(\@data_objects)},
             'Update strings found OK');
    my $expected_string = 'XYZ0987654321,0.9231,96,94,70,70,96,26,24,'.
        '1381735059,S02,73ca301a0a9e1b9cf87d4daf59eb2815';
    my $expected_strings = [ $expected_string, ];
    is_deeply($update_strings, $expected_strings,
              'Update string contents match expected values');
}

sub script_metaquery : Test(2) {
    my $cmd = "$script --query-path $irods_tmp_coll ".
        "--old-csv $tmp/$csv_name --in-place --logconf $logconf";
    $log->info("Running command '$cmd'");
    ok(system($cmd)==0, "Script with --in-place and metaquery exits OK");
    my $csv = Text::CSV->new ( { binary => 1 } );
    open my $fh, "<", "$tmp/$csv_name" ||
        $log->logcroak("Cannot open input '$tmp/$csv_name'");
    my $contents = $csv->getline_all($fh);
    close $fh || $log->logcroak("Cannot close input '$tmp/$csv_name'");
    my $expected_contents = [
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
            '1381735059',
            'S01',
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
            '1381735059',
            'S02',
            '73ca301a0a9e1b9cf87d4daf59eb2815',
        ],
    ];
    is_deeply($contents, $expected_contents,
              "Script in-place CSV output matches expected values");
}

sub script_stdin : Test(2) {
    my $fh;
    my $input_path = $tmp."/test_inputs.txt";
    open $fh, ">", $input_path ||
        $log->logcroak("Cannot open '$input_path'");
    foreach my $path (@irods_paths) {
        print $fh $path."\n";
    }
    close $fh || $log->logcroak("Cannot close '$input_path'");
    my $new_csv = "$tmp/fluidigm_qc_output.csv";
    my $cmd = "$script --new-csv $new_csv --old-csv $tmp/$csv_name ".
        "--logconf $logconf - < $input_path";
    $log->info("Running command '$cmd'");
    ok(system($cmd)==0, "Script with STDIN and new CSV file exits OK");

    # check the CSV output
    my $csv = Text::CSV->new ( { binary => 1 } );
    open $fh, "<", "$new_csv" ||
        $log->logcroak("Cannot open input '$new_csv'");
    my $contents = $csv->getline_all($fh);
    close $fh || $log->logcroak("Cannot close input '$new_csv'");
    my $expected_contents = [
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
            '1381735059',
            'S02',
            '73ca301a0a9e1b9cf87d4daf59eb2815',
        ],
    ];
    is_deeply($contents, $expected_contents,
              "New CSV output from script matches expected values");
}


1;
