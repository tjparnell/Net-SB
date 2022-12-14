package Net::SB::Folder;


use strict;
use English qw(-no_match_vars);
use Carp;
use File::Spec;
use File::Spec::Unix; # we pretend everything is unix based
use base 'Net::SB';

sub new {
	my ($class, $parent, $result) = @_;
	# create object based on the given result
	unless (defined $result and ref($result) eq 'HASH') {
		confess "Must call new() with a parsed JSON member result HASH!";
	}

	# result data
	my $self;
	if (exists $result->{resource}) {
		# there is an extra layer from bulk calls
		$self = $result->{resource};
	}
	else {
		$self = $result;
	}
	# typical data
	#    created_on => "2021-01-25T17:06:00Z",
	#    href => "https://api.sbgenomics.com/v2/files/600efa78e4b0cbef22dc2399",
	#    id => "600efa78e4b0cbef22dc2399",
	#    modified_on => "2021-01-25T17:06:00Z",
	#    name => "folder1",
	#    parent => "5d085d18e4b0acf73a39085d",
	#    project => "hci-bioinformatics-shared-reso/playground",
	#    type => "folder"

	# add parent and division information
	$self->{divobj} = $parent->{divobj};
	my $parent_class = ref $parent;
	if ($parent_class eq 'Net::SB::Folder') {
		$self->{projobj} = $parent->{projobj};
		$self->{path} = File::Spec::Unix->catfile($parent->path, $self->{name});
	}
	elsif ($parent_class eq 'Net::SB::Project') {
		$self->{projobj} = $parent;
		$self->{path} = $self->{name};
	}
	
	# remember the folders
	return bless $self, $class;
}

sub id {
	return shift->{id};
}

sub project {
	return shift->{id};
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
*pathname = \&path;

sub parent_id {
	return shift->{parent};
}

sub parent_obj {
	my $self = shift;
	my @dirs = File::Spec::Unix->splitdir($self->path);
	pop @dirs;
	my $p = File::Spec::Unix->catdir(@dirs);
	if (exists $self->{projobj}->{dirs}{$p}) {
		return $self->{projobj}->{dirs}{$p};
	}
	else {
		return $self->{projobj};
	}
}

sub list_contents {
	my $self = shift;
	my $url = sprintf "%s/list?offset=0&limit=100", $self->href;
	my @results = $self->execute('GET', $url);

	# process into file and folder objects
	my @contents;
	foreach my $f (@results) {
		my $type = $f->{type};
		if ($type eq 'file') {
			push @contents, Net::SB::File->new($self, $f);
		}
		elsif ($type eq 'folder') {
			my $folder = Net::SB::Folder->new($self, $f);
			push @contents, $folder;
			$self->{projobj}->{dirs}->{$folder->path} = $folder; # remember
		}
		else {
			carp sprintf "unknown object type '$type' for %s", $f->{name};
		}
	}
	return wantarray ? @contents : \@contents;
}

sub get_file_by_name {
	my ($self, $path) = @_;
	my (undef, $directory, $filename) = File::Spec->splitpath($path);
	if ($directory) {
		# we have a directory in here
		# reconstitute the entire path
		my @dirs = File::Spec::Unix->splitdir($self->path);
		push @dirs, File::Spec->splitdir($directory);
		my $newpath = File::Spec::Unix->catfile(@dirs, $filename);
		# then look for the file starting at project level going through directory tree
		return $self->{projobj}->get_file_by_name($newpath);
	}
	else {
		# looking for file in this path
		my $url = sprintf "%s/files?parent=%s&name=%s", $self->endpoint, $self->id,
			$filename;
		my @results = $self->execute('GET', $url);
		if (scalar @results == 1) {
			# there should only ever be one since there's no globbing
			my $f = shift @results;
			my $type = $f->{type};
			if ($type eq 'file') {
				return Net::SB::File->new($self, $f);
			}
			elsif ($type eq 'folder') {
				return Net::SB::Folder->new($self, $f);
			}
			else {
				carp sprintf "unknown object type '$type' for %s", $f->{name};
			}
		}
		else {
			# nothing found
			return;
		}
	}
}

sub recursive_list {
	my $self = shift;
	my $criteria = shift || undef;
	my @files;

	# recursively list all files
	my $top = $self->list_contents;
	while (@{$top}) {
		my $item = shift @{$top};
		if ($item->type eq 'file') {
			# keep the file
			push @files, $item;
		}
		else {
			# recurse into the folder
			push @files, $item;
			my $contents = $self->_recurse($item);
			push @files, @{$contents};
		}
	}

	# filter the file list
	if ($criteria) {
		my @filtered = grep {$_->pathname =~ /$criteria/} @files;
		return wantarray ? @filtered : \@filtered;
	}
	else {
		return wantarray ? @files : \@files;
	}
}

sub _recurse {
	my ($self, $folder) = @_;
	my @files;
	my $contents = $folder->list_contents;
	foreach my $item (@{$contents}) {
		if ($item->type eq 'file') {
			# keep the file
			push @files, $item;
		}
		else {
			# recurse into this subdirectory
			push @files, $item;
			my $contents2 = $self->_recurse($item);
			push @files, @{$contents2};
		}
	}
	return \@files;
}

sub delete {
	my $self = shift;
	return $self->execute('DELETE', $self->href);
}


1;

__END__

=head1 Net::SB::Folder

Class object representing a Folder on the Seven Bridges platform.

See Net::SB documentation for details.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  


