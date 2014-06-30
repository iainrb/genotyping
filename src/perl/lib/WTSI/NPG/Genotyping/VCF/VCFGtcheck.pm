
use utf8;

package WTSI::NPG::Genotyping::VCF::VCFGtcheck;

use JSON;
use Log::Log4perl::Level;
use Moose;
use WTSI::NPG::Runnable;

with 'WTSI::NPG::Loggable';

# front-end for bcftools gtcheck function
# use to cross-check sample results in a single VCF file for consistency
# parse results and output in useful formats

our $MAX_DISCORDANCE_KEY = 'MAX_DISCORDANCE';
our $PAIRWISE_DISCORDANCE_KEY = 'PAIRWISE_DISCORDANCE';

has 'environment' =>
    (is       => 'ro',
     isa      => 'HashRef',
     required => 1,
     default  => sub { \%ENV });

sub run {
    # run 'bcftools gtcheck' on the input; capture and parse the output
    # input is EITHER a VCF file as a single string, OR path to a VCF file
    # designate input type with the $from_stdin argument
    my $self = shift;
    my $input = shift;
    my $from_stdin = shift; # 1 if input is string for STDIN, 0 otherwise
    unless ($input) {
        $self->logcroak("No input supplied for bcftools gtcheck");
    }
    my $bcftools = $self->_find_bcftools();
    $self->logger->info("Running bcftools command: $bcftools");
    my (@args, @raw_results);
    if ($from_stdin) {
        unless ($self->_valid_vcf_fileformat($input)) {
            $self->logcroak("VCF input string for STDIN is not valid");
        }
        @args = ('gtcheck', '-', '-G', 1);
        @raw_results = WTSI::NPG::Runnable->new
            (executable  => $bcftools,
             arguments   => \@args,
             environment => $self->environment,
             logger      => $self->logger,
             stdin       => \$input)->run->split_stdout;
    } elsif (!(-e $input)){
        $self->logcroak("Input path '$input' does not exist");
    } else {
        @args = ('gtcheck', $input, '-G', 1);
        @raw_results = WTSI::NPG::Runnable->new
            (executable  => $bcftools,
             arguments   => \@args,
             environment => $self->environment,
             logger      => $self->logger)->run->split_stdout;
    }
    $self->logger->info("bcftools arguments: ".join(" ", @args));
    $self->logger->debug("bcftools command output:\n".join("", @raw_results));
    my %results;
    my $max = 0; # maximum pairwise discordance
    foreach my $line (@raw_results) {
        if ($line !~ /^CN/) { next; }
        my @words = split(/\s+/, $line);
        my $discordance = $words[1];
        my $sites = $words[2];
        my $sample_i = $words[4];
        my $sample_j = $words[5];
        if (!defined($discordance)) {
            $self->logcroak("Cannot parse discordance from output: $line");
        } elsif (!defined($sites)) {
            $self->logcroak("Cannot parse sites from output: $line");
        } elsif (!($sample_i && $sample_j)) {
            $self->logcroak("Cannot parse sample names from output: $line");
        }
        my $discord_rate;
        if ($sites == 0) { $discord_rate = 'NA'; }
        else { $discord_rate = $discordance / $sites; }
        $results{$sample_i}{$sample_j} = $discord_rate;
        $results{$sample_j}{$sample_i} = $discord_rate;
        if ($discord_rate > $max) { $max = $discord_rate; }
    }
    return (\%results, $max);
}

sub write_results_json {
    # write maximum pairwise discordance rates in JSON format
    my $self = shift;
    my $resultsRef = shift;
    my $maxDiscord = shift;
    my $outPath = shift;
    my %output = ($MAX_DISCORDANCE_KEY => $maxDiscord,
                  $PAIRWISE_DISCORDANCE_KEY => $resultsRef);
    open my $out, '>:encoding(utf8)', $outPath || $self->logcroak("Cannot open output $outPath");
    print $out encode_json(\%output);
    close $out || $self->logcroak("Cannot open output $outPath");
    return 1;
}

sub write_results_text {
    # write maximum pairwise discordance rates in text format
    # maximum appears in header
    # columns in body: sample_i, sample_j, pairwise discordance
    my $self = shift;
    my %results = %{ shift() };
    my $maxDiscord = shift;
    my $outPath = shift;
    my @samples = sort(keys(%results));
    open my $out, '>:encoding(utf8)', $outPath || $self->logcroak("Cannot open output $outPath");
    printf $out "# $MAX_DISCORDANCE_KEY: %.5f\n", $maxDiscord;
    print $out "# sample_i\tsample_j\tpairwise_discordance\n";
    foreach my $sample_i (@samples) {
        foreach my $sample_j (@samples) {
            if ($sample_i eq $sample_j) { next; }
            my @fields = ($sample_i,$sample_j,$results{$sample_i}{$sample_j});
            printf $out "%s\t%s\t%.5f\n", @fields;
        }
    }
    close $out || $self->logcroak("Cannot close output $outPath");
    return 1;
}

sub _find_bcftools {
    # check existence and version of the bcftools executable
    my $self = shift;
    my @raw_results = WTSI::NPG::Runnable->new
        (executable  => 'which',
         arguments   => ['bcftools',],
         environment => $self->environment,
         logger      => $self->logger)->run->split_stdout;
    my $bcftools = shift @raw_results;
    chomp $bcftools;
    if (!$bcftools) { $self->logcroak("Cannot find bcftools executable"); }
    my $version_string = `bcftools --version`;
    if ($version_string !~ /^bcftools 0\.2\.0-rc9/) {
        $self->logger->logwarn("Must have bcftools version >= 0.2.0-rc9");
    }
    return $bcftools;
}

sub _valid_vcf_fileformat {
    # Check if VCF string starts with a valid fileformat line
    # Eg. ##fileformat=VCFv4.1
    # Intended as a simple sanity check; does not validate rest of VCF
    my $self = shift;
    my $input = shift;
    my $valid = $input =~ /^##fileformat=VCFv[0-9]+\.[0-9]+/;
    return $valid;
}

no Moose;

1;

__END__