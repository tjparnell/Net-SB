#!/usr/bin/perl

use ExtUtils::MakeMaker;

WriteMakefile(
	"NAME"            => 'Net::SB',
	"VERSION_FROM"    => 'lib/Net/SB.pm',
	"ABSTRACT_FROM"   => 'lib/Net/SB.pm',
	"EXE_FILES"       => [],
	"LICENSE"         => 'artistic_2',
	"PREREQ_PM"       => {
		'Carp'              => 0,
		'GetOpt::Long'      => 0,
		'IO::File'          => 0,
		'File::Spec'        => 0,
		'List::Util'        => 1.45,
		'HTTP::Tiny'        => 0.077,
		'IO::Socket::SSL'   => 2.071,
		'JSON::PP'          => 0,
	},
	"META_MERGE"      => {
		'meta-spec'         => {version => 2},
		'resources'         => {
			'repository' => {
				'type'   => 'git',
				'url'    => 'https://github.com/tjparnell/net-sb.git',
				'web'    => 'https://github.com/tjparnell/net-sb',
			}
		},
	},
	"TEST_REQUIRES" => {
		"Test::More" => 0,
		"FindBin"    => 0
	},
	"test" => {
		"TESTS" => "t/*.t"
	}
);

