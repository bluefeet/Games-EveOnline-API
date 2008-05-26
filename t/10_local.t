#!/usr/bin/perl -w
use strict;
use warnings;

use Test::More tests => 6;
use English qw(-no_match_vars);
use Games::EveOnline::API;

my $api = Games::EveOnline::API->new();
$api->user_id( 3243311 );
$api->api_key( 'j2Eahd8WMABRb5cc3d304Ox1DJVFvY1fu2a0MmGbgq02bymX2ncOCn19CK4G3rk9' );
$api->character_id( 1972081734 );

my $feeds = [qw(
    skill_tree
    ref_types
    sovereignty
    characters
    character_sheet
    skill_in_training
)];

foreach my $feed (@$feeds) {
    $api->test_xml( "t/$feed.xml" );
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

