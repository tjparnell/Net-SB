package Net::SB::File;


use strict;
use Carp;
use File::Spec::Unix; # we pretend everything is unix based
use base 'Net::SB';

sub new {
	my ($class, $parent, $result) = @_;
	# create object based on the given result
	unless (defined $result and ref($result) eq 'HASH') {
		confess "Must call new() with a parsed JSON member result HASH!";
	}

	# result data
	my $self = $result;
	if (exists $result->{resource}) {
		# extra layer in bulk calls
		$self = $result->{resource};
	}
	# typical data from a listing
	#   href => "https://api.sbgenomics.com/v2/files/5d08657ee4b0acf73a3908a5",
	#   id => "5d08657ee4b0acf73a3908a5",
	#   name => "test_example.gtf",
	#   parent => "600efa78e4b0cbef22dc2399",
	#   project => "hci-bioinformatics-shared-reso/playground",
	#   type => "file"
	#
	# may also have additional information from bulk details
	#   created_on => "2021-01-15T22:11:38Z",
	#   metadata => {},
	#   modified_on => "2021-01-15T22:11:38Z",
	#   origin => {},
	#   size => 391,
	#   storage => {
	#     hosted_on_locations => [
	#   	"aws:us-east-1"
	#     ],
	#     type => "PLATFORM"
	#   },
	#   tags => [],

	# add parent and division information
	$self->{divobj} = $parent->{divobj};
	my $parent_class = ref $parent;
	if ($parent_class eq 'Net::SB::Folder') {
		$self->{projobj} = $parent->{projobj};
		$self->{path} = File::Spec::Unix->catfile($parent->path);
	}
	elsif ($parent_class eq 'Net::SB::Project') {
		$self->{projobj} = $parent;
		$self->{path} = q();
	}

	return bless $self, $class;
}

sub id {
	return shift->{id};
}

sub project {
	return shift->{project};
}

sub href {
	return shift->{href};
}

sub name {
	return shift->{name};
}

sub type {
	return shift->{type};
}

sub path {
	return shift->{path};
}

sub pathname {
	my $self = shift;
	my $path = $self->path;
	return $path ? File::Spec::Unix->catfile($path, $self->name) : $self->name;
}

sub parent_id {
	return shift->{parent};
}

sub parent_obj {
	my $self = shift;
	my $path = $self->path;
	return $path ? $self->{projobj}->{dirs}{$path} : $self->{projobj};
}

sub get_details {
	my $self = shift;
	my $result = shift || undef; # this may be from a bulk details collection
	unless ($result) {
		# need to collect from platform
		$result = $self->execute('GET', $self->href);
	}
	$self->{metadata}   = $result->{metadata};
	$self->{tags}       = $result->{tags};
	$self->{size}       = $result->{size};
	$self->{created_on} = $result->{created_on};
	$self->{modified_on} = $result->{created_on};
	$self->{origin}     = $result->{origin};
	$self->{storage}    = $result->{storage};
	return 1;
}

sub created {
	my $self = shift;
	unless (exists $self->{created_on}) {
		$self->get_details;
	}
	return $self->{created_on};
}

sub modified {
	my $self = shift;
	unless (exists $self->{modified_on}) {
		$self->get_details;
	}
	return $self->{modified_on};
}

sub size {
	my $self = shift;
	unless (exists $self->{size}) {
		$self->get_details;
	}
	return $self->{size};
}

sub download_link {
	my $self = shift;
	my $url = sprintf "%s/download_info", $self->href;
	my $result = $self->execute('GET', $url);
	if ($result and exists $result->{url}) {
		return $result->{url};
	}
	else {
		return;
	}
}

sub metadata {
	my $self = shift;
	unless (exists $self->{created_on}) {
		$self->get_details;
	}
	return $self->{metadata};
}

sub file_status {
	my $self = shift;
	unless (exists $self->{storage}) {
		$self->get_details;
	}
	if (
		exists $self->{storage}{hosted_on_locations} and
		defined $self->{storage}{hosted_on_locations}->[0]
	) {
		# example "aws:us-east-1"
		return $self->{storage}{hosted_on_locations}->[0];
	}
	elsif (
		exists $self->{storage}{volume} and
		defined $self->{storage}{volume}
	) {
		# example "hci-bioinformatics-shared-reso/hcibioinfo"
		return $self->{storage}{volume};
	}
	elsif (
		$self->{storage}{type} eq 'PLATFORM' and
		not exists $self->{storage}{hosted_on_locations}
	) {
		return 'Platform'; # I think?
	}
	else {
		return 'Unknown';
	}
}

sub add_metadata {
	my ($self, $data) = @_;
	unless ($data and ref $data eq 'HASH') {
		carp "need metadata HASH reference!";
		return;
	}
	my $url = sprintf "%s/metadata", $self->href;
	my $result = $self->execute('PUT', $url, undef, $data);
	if ($result) {
		$self->{metadata} = $result;
	}
}

sub delete {
	my $self = shift;
	return $self->execute('DELETE', $self->href);
}

1;

__END__

=head1 Net::SB::File

Class object representing a File on the Seven Bridges platform.

See Net::SB documentation for details.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  


