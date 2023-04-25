package Net::SB::File;


use strict;
use Carp;
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

	# minimum data
	unless (exists $self->{href} and exists $self->{id}) {
		confess "Missing critical href and/or id keys!";
	}
	$self->{name}    ||= q();    # this should never be null
	$self->{parent}  ||= q();
	$self->{type}    ||= 'file';
	
	# add parent and division information
	$self->{divobj} = $parent->{divobj};
	my $parent_class = ref $parent;
	if ($parent_class eq 'Net::SB::Folder') {
		$self->{projobj} = $parent->{projobj};
		$self->{project} ||= $parent->{projobj}->id;
		unless ( exists $self->{path} ) {
			$self->{path} = File::Spec::Unix->catfile($parent->path);
		}
	}
	elsif ($parent_class eq 'Net::SB::Project') {
		$self->{projobj} = $parent;
		$self->{project} ||= $parent->id;
		unless ( exists $self->{path} ) {
			$self->{path} = q();
		}
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
	$self->{name}        = $result->{name};
	$self->{parent}      = $result->{parent};
	$self->{project}     = $result->{project};
	$self->{metadata}    = $result->{metadata};
	$self->{tags}        = $result->{tags};
	$self->{size}        = $result->{size};
	$self->{created_on}  = $result->{created_on};
	$self->{modified_on} = $result->{created_on};
	$self->{origin}      = $result->{origin};
	$self->{storage}     = $result->{storage};
	
	return 1;
}

sub created_on {
	my $self = shift;
	unless (exists $self->{created_on}) {
		$self->get_details;
	}
	return $self->{created_on};
}

sub modified_on {
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

sub copy_to_project {
	my ($self, $project, $new_name) = @_;
	if ($project) {
		my $p_ref = ref $project;
		unless ($p_ref eq 'Net::SB::Project') {
			carp "unrecognized $p_ref project!";
			return;
		}
	}
	else {
		carp "must provide a project!";
		return;
	}
	my $data = {
		'project' => $project->id,
	};
	if ($new_name) {
		$data->{'name'} = $new_name;
	}
	my $url = sprintf "%s/actions/copy", $self->href;
	my $result = $self->execute('POST', $url, undef, $data);
	if ($result) {
		return $self->new($project, $result);
	}
	else {
		return;
	}
}

sub move_to_folder {
	my ($self, $folder, $new_name) = @_;
	if ($folder) {
		my $f_ref = ref $folder;
		unless ($f_ref eq 'Net::SB::Project') {
			carp "unrecognized $f_ref folder!";
			return;
		}
	}
	else {
		carp "must provide a folder!";
		return;
	}
	my $data = {
		'parent' => $folder->id,
	};
	if ($new_name) {
		$data->{'name'} = $new_name;
	}
	my $url = sprintf "%s/actions/move", $self->href;
	my $result = $self->execute('POST', $url, undef, $data);
	if ($result) {
		return $self->new($folder, $result);
	}
	else {
		return;
	}
}


1;

__END__

=head1 Net::SB::File - a File on the Seven Bridges platform.

=head1 DESCRIPTION

This represents a file on the Seven Bridges platform. It may be generated 
by listing methods from either a L<Net::SB::Project> or L<Net::SB::Folder>.

* L<Net::SB::Project/list_contents> 

* L<Net::SB::Project/recursive_list>

* L<Net::SB::Project/upload_file>

* L<Net::SB::Folder/list_contents> 

* L<Net::SB::Folder/recursive_list>

* L<Net::SB::Folder/upload_file>


=head1 METHODS

=over 4

=item new

Generally this object should only be initialized from a L<Net::SB::Project> or
L<Net::SB::Folder> object and not directly by end-users. It requires returned
JSON data from the Seven Bridges API and parent object information.

=item id

The hexadecimal identifier of the file.

=item project

Returns the name of the project to which this file belongs.

=item href

Returns the URL for this file.

=item name

The human name of the folder. 

=item type

Always returns C<file>.

=item path

Returns the full path of the parent folder, including upstream folders.

=item pathname

Returns the full path of the file, including upstream folders, and the file name.

=item parent_id

Returns the id of the parent folder.

=item parent_obj

Returns the stored object of the parent.

=item get_details

Makes an API call to collect additional data on the file object, including 
size, dates, and metadata. A parsed JSON result hash may be provided as the 
first argument from which to collect the extra information. 

=item created_on

Returns the C<created_on> value.

=item modified_on

Returns the C<modified_on> value.

=item size

Returns the size of the file as in integer in bytes.

=item metadata

Returns a reference to the metadata hash of key =E<gt> value metadata values.

=item file_status

Returns the location of where the file is stored, for example C<aws:us-east-1> 
for active storage on AWS S3. If the file is an imported file linked to an 
attached volume, the name of the volume is returned. Folders and archived 
files usually return C<Platform>. Anything else is returned as C<unknown>.

=item add_metadata(\%metadata)

Pass a reference to a metadata hash with the values to provide. If adding 
to existing metadata, first retrieve the metadata hash, make the changes, 
then call add_metadata().

=item download_link

Generates a download URL for downloading the file. This requires the file to be 
on active storage and neither archived nor linked from a storage volume. 
Returns the URL as a string. If a URL cannot be generated, nothing is returned 
without error, and the user should assume the file is unavailable for download.

=item copy_to_project($project)

Pass a L<Net::SB::Project> object into which this file should be copied. The
current user must have write permissions for the destination project. Note that
if an existing file with the same name already exists, the platform may
automatically rename the file, usually by prefixing the name with an
incrementing digit and underscore. A new file name for the destination project
may be provided as a second value, if desired, to avoid automatic renaming.
Folders are not supported; files are copied to the root folder.

=item move_to_folder($folder)

Pass a L<Net::SB::Folder> object into which this file should be copied. The 
folder must be in the same project, not a different project. Note
that if an existing file with the same name already exists, the platform may
automatically rename the file, usually by prefixing the name with an
incrementing digit and underscore. A new file name for the destination project
may be provided as a second value if desired, to avoid this behavior. 

=item delete

Delete this file from the platform.

=back

=head2 Inherited Methods

These are available methods inherited from L<Net::SB> that may be useful. See 
therein for details.

=over 4

=item credentials

=item division

=item token

=item endpoint

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


