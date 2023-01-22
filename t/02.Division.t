#!/usr/bin/perl -w

# Test script for Net::SB

use strict;
use Test::More;
use File::Spec;
use FindBin '$Bin';

BEGIN {
    plan tests => 12;
}

require_ok 'Net::SB::Division'
	or BAIL_OUT "Cannot load Net::SB::Division";

my $cred_path = File::Spec->catfile( $Bin, "fake_credentials" );


# we fake making a division object to avoid actual network activity
my $div = Net::SB::Division->new(
	cred    => $cred_path,
	div     => 'home',   # 'hci-bioinformatics-shared-reso'
	name    => 'Home',  # 'HCI Bioinformatics Shared Resource'
	href    => 'https://api.sbgenomics.com/v2/divisions/home',  # https://api.sbgenomics.com/v2/divisions/hci-bioinformatics-shared-reso
	cred    => $cred_path,  # ~/.sevenbridges/credentials
	token   => undef, 
	verbose => 0,
	end     => 'https://api.sbgenomics.com/v2', # https://api.sbgenomics.com/v2
	partsz  => (32 * 1024 * 1024),
	bulksz  => 100,
	napval  => 2,
);

isa_ok($div, 'Net::SB::Division', 'Net::SB::Division object' );
is( $div->credentials, $cred_path, 'credential file' );
is( $div->endpoint, 'https://api.sbgenomics.com/v2', 'default endpoint' );
is( $div->token, 'd0123456789abcdefghijklmnopqrstu', 'credential token' );
is( $div->verbose, 0, 'default verbosity' );

is( $div->division, 'home', 'given division' );
is( $div->id, 'home', 'division id' );
is( $div->name, 'Home', 'division name' );
is( $div->href, 'https://api.sbgenomics.com/v2/divisions/home', 'division href' );
is( $div->division, 'home', 'division name' );
is( $div->division, 'home', 'division name' );
