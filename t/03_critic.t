#!/usr/bin/perl -w
use strict;
use warnings;

use Test::More;
use English qw(-no_match_vars);

plan( skip_all => 'Author test.  Set TEST_AUTHOR env var to a true value to run.' ) if !$ENV{TEST_AUTHOR};

eval( 'use Test::Perl::Critic' );
plan( skip_all => 'Test::Perl::Critic required to run this test' ) if $EVAL_ERROR;

all_critic_ok();

