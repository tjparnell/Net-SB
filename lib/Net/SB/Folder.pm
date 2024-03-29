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
	if (ref $class) {
		$class = ref $class;
	}

	# create object based on the given result
	unless (defined $result and ref($result) eq 'HASH') {
		confess "Must call new() with a parsed JSON member result HASH!";
	}
	my $self = $result;
	if (exists $result->{resource}) {
		# extra layer in bulk calls
		$self = $result->{resource};
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

sub created_on {
	my $self = shift;
	unless ( exists $self->{created_on} ) {
		$self->_get_details;
	}
	return $self->{created_on};
}

sub modified_on {
	my $self = shift;
	unless ( exists $self->{modified_on} ) {
		$self->_get_details;
	}
	return $self->{modified_on};
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
			$self->_encode($filename);
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
	my $limit = shift || 0;
	$limit = int $limit;
	my @files;
	if ($limit) {
		$limit += scalar( File::Spec::Unix->splitdir( $self->path ) );
		# increase the limit to compensate for current folder
	}

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
			my $contents = $self->_recurse($item, $limit);
			if ( $contents and scalar @{ $contents } ) {
				push @files, @{$contents};
			}
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
	my ($self, $folder, $limit) = @_;
	if ($limit) {
		my @dirs = File::Spec::Unix->splitdir($folder->path);
		return if (scalar @dirs >= $limit);
	}
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
			if ($contents2 and scalar @{ $contents2 } ) {
				push @files, @{ $contents2 };
			}
		}
	}
	return \@files;
}

sub list_files_by_task {
	my $self = shift;
	my $task = shift || undef;
	return $self->{projobj}->list_files_by_task($task, $self);
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

=head1 Net::SB::Folder - a Folder on the Seven Bridges platform

=head1 DESCRIPTION

This represents a folder on the Seven Bridges platform. It may be generated 
from the following L<Net::SB::Project> methods:

* L<Net::SB::Project/list_contents> 

* L<Net::SB::Project/recursive_list>

* L<Net::SB::Project/create_folder>

As the hierarchy of folders are browsed within a project, the folder objects are 
cached in the Project object, such that re-visiting a folder during a subsequent 
traversal does not necessitate expensive remote queries. 

=head1 METHODS

=over 4

=item new

Generally this object should only be initialized from a L<Net::SB::Project> 
object and not directly by end-users. It requires returned JSON data from the 
Seven Bridges API and parent object information.

=item id

The hexadecimal identifier of the folder, such as C<600efa78e4b0cbef22dc2399>.

=item project

Returns the name of the project to which this folder belongs, such as 
C<RFranklin/my-project>.

=item href

Returns the URL for this folder.

=item name

The human name of the folder, such as C<my-folder-1>. 

=item type

Always returns C<folder>.

=item path

=item pathname

Returns the full path of the folder, including upstream folders.

=item parent_id

Returns the id of the parent folder, such as C<5d085d18e4b0acf73a39085d>.

=item parent_obj

Returns the stored object of the parent.

=item created_on

Returns the C<created_on> value, such as C<2021-01-25T17:06:00Z> .

=item modified_on

Returns the C<modified_on> value.

=item list_contents

List all files and folders in the folder. Does not recurse. Returns an array or
array reference of L<Net::SB::File> and L<Net::SB::Folder> objects as
appropriate.

=item recursive_list

=item recursive_list($regex)

=item recursive_list($regex, $limit)

Recursively list all file and folders within the folder, recursing into folders
as necessary until everything is found. Optionally pass a Perl regular
expression as an argument for filtering the found objects based on their
pathname, i.e. folders plus filename. Returns an array or array reference of
L<Net::SB::File> and L<Net::SB::Folder> objects as appropriate.

An integer may optionally be provided as a second argument to limit the recursive 
limit relative to the starting point, where 1 is the current folder. If a filter 
is not needed, pass an empty or undefined value as the first argument.

=item get_file_by_name($filepath)

Provide a file path, either a filename in the current folder, or with folder path. 
The file is searched for by recursing as necessary into each folder. If the file 
(or folder) is found, it is returned as an object. The file path should be a 
scalar value, such as C<analysis/results/summary.xlsx>.

=item list_files_by_task($task)

List files generated by a specific analysis task. The task identifier (or 
L<Net::SB::Task> object) must be provided.

=item create_folder($new_folder_name)

Pass a folder or path of multiple folders. The folder is first searched for on 
the platform, and if not found, is generated. Intermediate folders are generated 
as necessary. A L<Net::SB::Folder> object is returned.

=item upload_file($remote_filepath, $local_filepath, $overwrite)

Pass two or three parameters. 

* The first is the remote file path, including folder(s) and file name, 
in the Project.

* The second is the local file path of the file to be uploaded.  

* The third is an optional boolean value to overwrite the file. The default is false.

Intermediate folders, if present, are searched for and if necessary generated. 

=item delete

Deletes the folder from the platform. Only an empty folder can be deleted, otherwise
you will likely receive errors.

=back

=head2 Inherited Methods

These are available methods inherited from L<Net::SB> that may be useful. See 
therein for details.

=over 4

=item credentials

=item division

=item token

=item endpoint

=item part_size

=item execute

=item verbose

=back

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  


