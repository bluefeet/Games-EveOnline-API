use strict;
use warnings;

use inc::Module::Install;

name     'Games-EveOnline-API';
perl_version '5.008003';
all_from 'lib/Games/EveOnline/API.pm';

requires 'Moose' => 0.39;
requires 'LWP::Simple' => 0;
requires 'XML::Simple' => 0;

build_requires 'Test::More' => 0.62;

WriteAll;

