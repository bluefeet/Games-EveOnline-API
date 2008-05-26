#!/usr/bin/perl -w
use strict;
use warnings;

use Test::More tests => 3;
use English qw(-no_match_vars);
use Games::EveOnline::API;

my $api = Games::EveOnline::API->new( test_mode => 1 );

my $feeds = [qw(
    skill_tree
    ref_types
    sovereignty
)];

foreach my $feed (@$feeds) {
    my $api_data = $api->$feed();

    my $dump = read_file( "t/$feed.dump" );
    my $dump_data = eval( $dump );
    die("Unable to eval $feed dump: $EVAL_ERROR") if ($EVAL_ERROR);

    is_deeply( $api_data, $dump_data, "API result matches dumped result for $feed" );
}

sub read_file {
    my ($file) = @_;

    open my $fh, '<', $file or die "Failed to open '$file': $OS_ERROR";
    my $content = do { local $INPUT_RECORD_SEPARATOR; <$fh> };

    return $content;
}

