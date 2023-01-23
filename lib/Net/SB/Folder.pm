package Net::SB::Folder;


use warnings;
use strict;
use Carp;
use File::Spec;
use File::Spec::Unix; # we pretend everything is unix based
use base 'Net::SB';

our $VERSION = Net::SB->VERSION;

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

	# minimum data
	unless (exists $self->{href} and exists $self->{id}) {
		confess "Missing critical href and/or id keys!";
	}
	$self->{name}    ||= q();    # this should never be null
	$self->{parent}  ||= q();
	$self->{type}    ||= 'folder';
	
	# add parent and division information
	$self->{divobj} = $parent->{divobj};
	my $parent_class = ref $parent;
	if ($parent_class eq 'Net::SB::Folder') {
		$self->{projobj} = $parent->{projobj};
		$self->{project} ||= $parent->{projobj}->id;
		unless ( exists $self->{path} ) {
			$self->{path} = File::Spec::Unix->catfile($parent->path, $self->{name});
		}
	}
	elsif ($parent_class eq 'Net::SB::Project') {
		$self->{projobj} = $parent;
		$self->{project} ||= $parent->id;
		unless ( exists $self->{path} ) {
			$self->{path} = $self->{name};
		}
	}
	
	# remember the folders
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

sub create_folder {
	my ($self, $path) = @_;
	return unless $path;
	$path =~ s/\/|\\$//; # remove trailing slash, creates problems
	my @dirs = File::Spec->splitdir($path);

	if (scalar @dirs > 1) {
		# making more than one directory at a time
		# for simplicity and avoid code redundancy, just do this from the 
		# project root directory
		# there is a potential cost of code inefficiency here....
		my $fullpath = File::Spec::Unix->catpath(
			File::Spec::Unix->splitdir($self->path),
			@dirs
		);
		return $self->{projobj}->create_folder($fullpath);
	}
	else {
		# make a single directory in here
		my $url = sprintf "%s/files", $self->endpoint;
		my $data = {
			'name'   => $path,
			'type'   => 'folder',
			'parent' => $self->id
		};
		my $result = $self->execute('POST', $url, undef, $data);
		if ($result) {
			my $folder = Net::SB::Folder->new($self, $result);
			$self->{projobj}{dirs}{$folder->path} = $folder;
			return $folder;
		}
		else {
			carp "cannot make $path!";
		}
	}
}

sub upload_file {
	my ($self, $target_filepath, $local_filepath, $overwrite) = @_;
	return unless $target_filepath;
	return unless ($local_filepath and -e $local_filepath);
	unless (defined $overwrite) {
		$overwrite = 0;
	}
	if ($self->verbose) {
		printf " > upload local file '%s' to remote folder '%s' as '%s', overwriting %s\n",
			$local_filepath, $self->name, $target_filepath, $overwrite ? 'Y' : 'N';
	}

	# first check for directory 
	my (undef, $target_dir, $target_filename) = File::Spec->splitpath($target_filepath);
	if ($target_dir) {
		# user wants this in a folder that is under this one
		# we cannot do that here, so need to redirect to parent object
		# first make a full path, then forward on to project
		my $full_path = File::Spec::Unix->catpath(
			$self->path,
			File::Spec->splitpath($target_dir),
			$target_filename
		);
		return $self->{projobj}->upload_file($full_path, $local_filepath, $overwrite);
	}

	# check file size
	unless (-e $local_filepath and -r _ ) {
		carp " file '$local_filepath' cannot be read!";
		return;
	}
	my @st = stat $local_filepath;
	my $file_size = $st[7];

	# check remote file
	my $remote_file = $self->get_file_by_name($target_filename);
	if ($remote_file) {
		if ($overwrite) {
			printf "  Overwriting remote file %s, size %d, modified on %s\n",
				$local_filepath, $remote_file->size, $remote_file->modified;
		}
		else {
			printf "  Skipping remote file %s, size %d, modified on %s\n",
				$local_filepath, $remote_file->size, $remote_file->modified;
			return;
		}
	}

	# initialize upload
	my $url = sprintf "%s/upload/multipart", $self->endpoint;
	if ($overwrite) {
		$url .= '?overwrite=true';
	}
	if ($self->verbose) {
		my $p = $self->part_size;
		printf "   >> Local file is %d bytes, will upload in %d parts of %d bytes\n",
			$file_size, 
			int( ($file_size + $p - 1) / $p ),
			$p;
	}
	my $data = {
		'parent'    => $self->id,
		'name'      => $target_filename,
		'size'      => $file_size,
		'part_size' => $self->part_size
	};
	my $upload = $self->execute('POST', $url, undef, $data);
	if ($upload) {
		# pass off to generic uploader function
		return $self->{projobj}->_upload_file($self, $local_filepath, $file_size, $upload);
	}
	else {
		carp "error uploading!";
		return;
	}
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


