#!/usr/bin/perl -w

# Test script for Net::SB

use strict;
use Test::More;
use File::Spec;
use FindBin '$Bin';

BEGIN {
    plan tests => 21;
}

require_ok 'Net::SB::Division'
	or BAIL_OUT "Cannot load Net::SB::Division";
require_ok 'Net::SB::Member'
	or BAIL_OUT "Cannot load Net::SB::Member";

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


# we make a fake member to avoid actual network activity
my $project = Net::SB::Member->new(
	$div,
	{
	 country     => 'United States',
	 last_name   => 'Me',
	 username    => 'testme',
	 email       => 'test.me@nowhere.edu',
	 href        => 'https://api.sbgenomics.com/v2/users/home/testme',
	 first_name  => 'Test',
	 city        => q(),
	 role        => 'MEMBER',
	 state       => q(),
	 affiliation => q(),
	 zip_code    => q(),
	 phone       => q(),
	 address     => q()
	},
);

isa_ok( $project, 'Net::SB::Member', 'Net::SB::Member object' );

# inherited functions
is( $project->division, 'home', 'Member division');
is( $project->credentials, $cred_path, 'Member credential file' );
is( $project->endpoint, 'https://api.sbgenomics.com/v2', 'Member endpoint' );
is( $project->token, 'd0123456789abcdefghijklmnopqrstu', 'Member token' );
is( $project->verbose, 0, 'Member verbosity' );


# implicit functions
is( $project->id, 'home/testme', 'Member ID' );
is( $project->href, 'https://api.sbgenomics.com/v2/users/home/testme', 'Member href' );
is( $project->username, 'testme', 'Member username' );
is( $project->email, 'test.me@nowhere.edu', 'Member email address' );
is( $project->name, 'Test Me', 'Member name' );
is( $project->first_name, 'Test', 'Member first name' );
is( $project->last_name, 'Me', 'Member last name' );
is( $project->role, 'MEMBER', 'Member role' );




