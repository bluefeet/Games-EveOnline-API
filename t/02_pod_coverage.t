#!/usr/bin/perl -w
use strict;
use warnings;

use Test::More;
use English qw(-no_match_vars);

plan( skip_all => 'Author test.  Set TEST_AUTHOR env var to a true value to run.' ) if !$ENV{TEST_AUTHOR};

eval( 'use Test::Pod::Coverage 1.00' );
plan( skip_all => 'Test::Pod::Coverage 1.00 required for testing POD coverage' ) if $EVAL_ERROR;

all_pod_coverage_ok();

