#!/usr/bin/perl -w

# Test script for Net::SB

use strict;
use Test::More;
use File::Spec;
use FindBin '$Bin';

BEGIN {
    plan tests => 7;
}

require_ok 'Net::SB'
	or BAIL_OUT "Cannot load Net::SB";

my $cred_path = File::Spec->catfile( $Bin, "fake_credentials" );

my $sb = Net::SB->new(
	'cred'      => $cred_path,
);

isa_ok($sb, 'Net::SB', 'Net::SB object');
is( $sb->credentials, $cred_path, 'credential file' );
is( $sb->division, undef, 'default division' );
is( $sb->endpoint, 'https://api.sbgenomics.com/v2', 'default endpoint' );
is( $sb->token, 'd0123456789abcdefghijklmnopqrstu', 'credential token' );
is( $sb->verbose, 0, 'default verbosity' );
