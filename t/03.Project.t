#!/usr/bin/perl -w

# Test script for Net::SB

use strict;
use Test::More;
use File::Spec;
use FindBin '$Bin';

BEGIN {
    plan tests => 27;
}

require_ok 'Net::SB::Division'
	or BAIL_OUT "Cannot load Net::SB::Division";
require_ok 'Net::SB::Project'
	or BAIL_OUT "Cannot load Net::SB::Project";

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


# we make a fake project to avoid actual network activity
my $project = Net::SB::Project->new(
	$div,
	{
		href        => 'https://api.sbgenomics.com/v2/home/test',
		id          => 'home/test',
		name        => 'Test',
		created_on  => '2019-06-18T03:40:09Z',
		created_by  => 'home/me',
		modified_on => '2019-06-18T03:40:09Z',
		description => 'This is a test',
		root_folder => '5678912345abcdefghi12340'
	},
);

isa_ok( $project, 'Net::SB::Project', 'Net::SB::Project object' );

# inherited functions
is( $project->division, 'home', 'Project division');
is( $project->credentials, $cred_path, 'Project credential file' );
is( $project->endpoint, 'https://api.sbgenomics.com/v2', 'Project endpoint' );
is( $project->token, 'd0123456789abcdefghijklmnopqrstu', 'Project token' );
is( $project->verbose, 0, 'Project verbosity' );


# implicit functions
is( $project->id, 'home/test', 'Project ID' );
is( $project->project, 'home/test', 'Project project' );
is( $project->name, 'Test', 'Project name' );
is( $project->href, 'https://api.sbgenomics.com/v2/home/test', 'Project href' );
is( $project->description, 'This is a test', 'Project description' );
is( $project->created_on, '2019-06-18T03:40:09Z', 'Project creation time' );
is( $project->modified_on, '2019-06-18T03:40:09Z', 'Project modification time' );


# implicit returned object functions
my $folder = $project->root_folder;
isa_ok($folder, 'Net::SB::Folder', 'Project root folder');
is( $folder->id, '5678912345abcdefghi12340', 'Root folder ID' );
is( $folder->name, q(), 'Root folder name');
is( $folder->path, q(), 'Root folder path');

my $owner = $project->created_by;
isa_ok($owner, 'Net::SB::Member', 'Project creator');
is($owner->id, 'home/me', 'Creator ID');
is($owner->name, 'me', 'Creator Name');



