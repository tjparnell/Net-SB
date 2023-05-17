#!/usr/bin/perl -w

# Test script for Net::SB

use strict;
use Test::More;
use File::Spec;
use FindBin '$Bin';

BEGIN {
    plan tests => 28;
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


# we make a fake file object to avoid actual network activity
my $file = Net::SB::File->new(
	$folder,
	{
		href => 'https://api.sbgenomics.com/v2/files/5d08657ee4b0acf73a3908a5',
		id => '5d08657ee4b0acf73a3908a5',
		name => 'test_example.gtf',
		parent => '600efa78e4b0cbef22dc2399',
		project => 'home/test',
		type => 'file',
		created_on => '2021-01-15T22:11:38Z',
		metadata => {},
		modified_on => '2021-01-15T22:11:38Z',
		origin => {},
		size => 391,
		storage => {
		  hosted_on_locations => [
			'aws:us-east-1'
		  ],
		  type => 'PLATFORM'
		},
		tags => [],
	}
);

# this is normally generated, but since we're faking everything, gotta create it
$project->{dirs}{folder1} = $folder;



# inherited functions
is( $file->division, 'home', 'File division');
is( $file->credentials, $cred_path, 'File credential file' );
is( $file->endpoint, 'https://api.sbgenomics.com/v2', 'File endpoint' );
is( $file->token, 'd0123456789abcdefghijklmnopqrstu', 'File token' );
is( $file->verbose, 0, 'File verbosity' );


# implicit functions
is( $file->id, '5d08657ee4b0acf73a3908a5', 'File ID' );
is( $file->project, 'home/test', 'File project' );
is( $file->name, 'test_example.gtf', 'File name' );
is( $file->href, 'https://api.sbgenomics.com/v2/files/5d08657ee4b0acf73a3908a5', 'File href' );
is( $file->type, 'file', 'File type' );
is( $file->path, 'folder1', 'File path' );
is( $file->pathname, 'folder1/test_example.gtf', 'File path' );
is( $file->parent_id, '600efa78e4b0cbef22dc2399', 'File parent ID' );
is( $file->created_on, '2021-01-15T22:11:38Z', 'File creation date' );
is( $file->modified_on, '2021-01-15T22:11:38Z', 'File modification date' );
is( $file->size, 391, 'File size' );

# returned object
my $parent = $file->parent_obj;
isa_ok($parent, 'Net::SB::Folder', 'File parent object' );
is($parent->id, '600efa78e4b0cbef22dc2399', 'File parent object ID' );




