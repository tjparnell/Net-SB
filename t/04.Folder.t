#!/usr/bin/perl -w

# Test script for Net::SB

use strict;
use Test::More;
use File::Spec;
use FindBin '$Bin';

BEGIN {
    plan tests => 23;
}

require_ok 'Net::SB::Division'
	or BAIL_OUT "Cannot load Net::SB::Division";
require_ok 'Net::SB::Project'
	or BAIL_OUT "Cannot load Net::SB::Project";
require_ok 'Net::SB::Folder'
	or BAIL_OUT "Cannot load Net::SB::Folder";

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


# we make a fake folder to avoid actual network activity
my $folder = Net::SB::Folder->new(
	$project,
	{
        created_on => '2021-01-25T17:06:00Z',
        href => 'https://api.sbgenomics.com/v2/files/600efa78e4b0cbef22dc2399',
        id => '600efa78e4b0cbef22dc2399',
        modified_on => '2021-01-25T17:06:00Z',
        name => 'folder1',
        parent => '5678912345abcdefghi12340',
        project => 'home/test',
        type => 'folder'
	},
);

isa_ok( $folder, 'Net::SB::Folder', 'Net::SB::Folder object' );


# inherited functions
is( $folder->division, 'home', 'Folder division');
is( $folder->credentials, $cred_path, 'Folder credential file' );
is( $folder->endpoint, 'https://api.sbgenomics.com/v2', 'Folder endpoint' );
is( $folder->token, 'd0123456789abcdefghijklmnopqrstu', 'Folder token' );
is( $folder->verbose, 0, 'Folder verbosity' );


# implicit functions
is( $folder->id, '600efa78e4b0cbef22dc2399', 'Folder ID' );
is( $folder->project, 'home/test', 'Folder project' );
is( $folder->name, 'folder1', 'Folder name' );
is( $folder->href, 'https://api.sbgenomics.com/v2/files/600efa78e4b0cbef22dc2399', 'Folder href' );
is( $folder->type, 'folder', 'Folder type' );
is( $folder->path, 'folder1', 'Folder path' );


# returned object
my $parent = $folder->parent_obj;
isa_ok($parent, 'Net::SB::Project', 'Folder parent object' );
is($parent->id, 'home/test', 'Folder parent object ID' );




