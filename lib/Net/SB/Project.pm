package Net::SB::Project;

use warnings;
use strict;
use English qw(-no_match_vars);
use Carp;
use File::Spec;
use File::Spec::Unix;
use IO::File;
use base 'Net::SB';
use Net::SB::Member;
use Net::SB::File;
use Net::SB::Folder;

sub new {
	my ($class, $parent, $result) = @_;

	# create object based on the given result
	unless (defined $result and ref($result) eq 'HASH') {
		confess "Must call new() with a parsed JSON project result HASH!"
	}
	my $self = $result;
	# typical structure
	#   href => "https://api.sbgenomics.com/v2/projects/hci-bioinformatics-shared-reso/playground",
	#   id => "hci-bioinformatics-shared-reso/playground",
	#   name => "playground"
	#   created_by => "hci-bioinformatics-shared-reso/tjparnell",
	#   created_on => "2019-06-18T03:40:09Z",
	#   modified_on => "2019-07-01T21:54:20Z",

	# add division, which the parent should always be
	$self->{divobj} = $parent;

	# keep a hash of all folders encountered
	$self->{dirs} = {};

	return bless $self, $class;
}

sub _get_details {
	my $self = shift;
	my $result = $self->execute('GET', $self->{href});
	foreach my $key (keys %{$result}) {
		unless ( exists $self->{$key} ) {
			$self->{$key} = $result->{$key};
		}
	}
}

sub id {
	return shift->{id};
}

sub project {
	return shift->{id};
}

sub href {
	my $self = shift;
	return $self->{href};
}

sub name {
	my $self = shift;
	return $self->{name};
}

sub description {
	my $self = shift;
	unless ( exists $self->{description} ) {
		$self->_get_details;
	}
	return $self->{description} || undef;
}

sub root_folder {
	my $self = shift;
	unless ( exists $self->{root_folder} ) {
		$self->_get_details;
	}
	my $id = $self->{root_folder};
	my $data = {
		'id'        => $id,
		'href'      => sprintf("%s/files/%s", $self->endpoint, $id),
		'name'      => q(),
		'project'   => $self->id,
		'type'      => 'folder',
	};
	return Net::SB::Folder->new($self, $data);
}

sub billing_group {
	my $self = shift;
	unless ( exists $self->{billing_group} ) {
		$self->_get_details;
	}
	return $self->{billing_group};
}

sub created_by {
	my $self = shift;
	unless ( exists $self->{created_by} ) {
		$self->_get_details;
	}
	my $id = $self->{created_by};
	my $data = {
		'id'        => $id,
		'username'  => $id,
		'href'      => sprintf("%s/members/%s", $self->{href}, $id),
	};
	return Net::SB::Member->new($self, $data);
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

sub location {
	my $self = shift;
	unless ( exists $self->{location} ) {
		$self->_get_details;
	}
	return $self->{location};
}

sub permissions {
	my $self = shift;
	unless ( exists $self->{permissions} ) {
		$self->_get_details;
	}
	return $self->{permissions};
}

sub update {
	my $self = shift;
	my %data = @_;
	unless (%data) {
		carp "no data to update!?";
		return;
	}

	# set URL, using simple POST since I don't think client supports PATCH
	my $url = $self->href . '?_method=PATCH';

	# execute
	my $result = $self->execute('POST', $url, undef, \%data);

	# blindly replace all the update key values
	foreach my $key (keys %{$result}) {
		$self->{$key} = $result->{$key};
	}

	return 1;
}

sub list_members {
	my $self = shift;
	unless ($self->{members}) {
		my $url = $self->{href} . '/members';
		my @results = $self->execute('GET', $url);
		my @members = map { Net::SB::Member->new($self, $_) } @results;
		$self->{members} = \@members;
	}
	return wantarray ? @{ $self->{members} } : $self->{members};
}

sub add_member {
	my $self = shift;
	my $member = shift;
	my %permissions = @_;
	unless ($member) {
		carp "Must pass a member object or username to add a member!";
		return;
	}

	# set default permissions
	$permissions{'read'} ||= 'true';
	$permissions{'copy'} ||= 'true';

	# data
	my $data = {
		permissions => \%permissions,
	};

	# get member username
	if (ref($member) eq 'Net::SB::Member') {
		$data->{username} = $member->id; # must be longform username division/username
		if ($self->verbose) {
			printf " >> adding member id %s\n", $data->{name};
		}
	}
	elsif (ref($member) eq 'Net::SB::Team') {
		$data->{username} = $member->id;
		$data->{type} = 'TEAM';
		if ($self->verbose) {
			printf " >> adding team id %s\n", $data->{name};
		}
	}
	elsif ($member =~ m/^ [a-z0-9\-]+ \/ [\w\-\.]+ $/x) {
		# looks like a typical id
		$data->{username} = $member;
		if ($self->verbose) {
			printf " >> adding given member id %s\n", $data->{name};
		}
	}
	elsif ($member =~ m/^ [\w\.\-]+ @ [\w\.\-]+ \. (?: com | edu | org ) $/x) {
		# looks like an email address
		$data->{email} = $member;
		if ($self->verbose) {
			printf " >> adding given member email %s\n", $data->{name};
		}
	}
	else {
		carp "unrecognized member format!";
		return;
	}

	# execute
	my $url = $self->href . '/members';
	my $result = $self->execute('POST', $url, undef, $data);
	return $result ? Net::SB::Member->new($self, $result) : undef;
}

sub modify_member_permission {
	my $self = shift;
	my $member = shift;
	my %permissions = @_;

	unless ($member) {
		carp "Must pass a member object or username to add a member!";
		return;
	}
	unless (%permissions) {
		carp "Must pass a permissions to change!";
	}

	# get member username
	my $username;
	if (ref($member) eq 'Net::SB::Member') {
		$username = $member->id; # must be longform username division/username
		if ($self->verbose) {
			printf " >> updating member id %s\n", $username;
		}
	}
	elsif (ref($member) eq 'Net::SB::Team') {
		$username = $member->id;
		if ($self->verbose) {
			printf " >> updating team id %s\n", $username;
		}
	}
	elsif ($member =~ m/^ [a-z0-9\-]+ \/ [\w\-\.]+ $/x) {
		# looks like a typical id
		$username = $member;
		if ($self->verbose) {
			printf " >> updating given id %s\n", $username;
		}
	}
	else {
		carp "unrecognized member format '$member'!";
		return;
	}

	# execute
	my $url = $self->href . "/members/$username/permissions?_method=PATCH";
	my $result = $self->execute('POST', $url, undef, \%permissions);
	return $result;
}

sub list_contents {
	my $self = shift;
	my $url = sprintf "%s/files?offset=0&limit=100&project=%s", $self->endpoint,
		$self->id;
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
			$self->{dirs}{$folder->path} = $folder; # remember
		}
		else {
			carp sprintf "unknown object type '$type' for %s", $f->{name};
		}
	}
	return wantarray ? @contents : \@contents;
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

sub get_file_by_name {
	# this is a misnomer function
	# we could be given either a file or a folder name, without knowing a priori what
	# is - the API doesn't distinguish, and we can return either 
	my ($self, $filepath) = @_;
	return unless defined $filepath;
	$filepath =~ s/(\/|\\)$//; # remove trailing slash, creates problems

	# split the path, assuming unix - this may wreck havoc on DOS computers
	my @bits = File::Spec::Unix->splitdir($filepath);
	# printf "  >> checking '%s' with %d bits\n", $filepath, scalar(@bits);
	if (scalar @bits > 1) {
		# more than one level
		my $filename = pop @bits; # the last item, may not actually be a filename
		# we will need to do a directory walk to find the parent
		my $parent = $self; # start at the root
		TREEWALK:
		for my $d (0..$#bits) {
			my $dir = $bits[$d];
			my $dirpath = $dir;
			if ($d > 0) {
				# only concatenate if there is more than one
				$dirpath = File::Spec::Unix->catdir(@bits[0..$d]);
			}
			# print "  >> checking level $d for '$dirpath'\n";

			# start looking for this directory
			if (exists $self->{dirs}{$dirpath}) {
				# we know about this one
				# print "  >> found in object memory\n";
				$parent = $self->{dirs}{$dirpath};
				next TREEWALK;
			}
			else {
				# need to check on the platform
				# print ">> looking in parent for $dir\n";
				my $folder = $parent->get_file_by_name($dir);
				if ($folder) {
					# this one exists on the platform
					# print "  >> found next folder\n";
					$self->{dirs}{$dirpath} = $folder;
					$parent = $folder;
					next TREEWALK;
				}
				else {
					# not found
					# we can't go any further
					# print "  >> can't find next folder\n";
					if ($d < $#bits) {
						# there are more folders to go but we're stuck so bail
						return;
					}
				}
			}
		}
		# finished walking through the directory tree
		# parent should be the final folder we want
		# now look
		# print "  >> finished tree walk of full directory path\n";
		return $parent->get_file_by_name($filename);
	}

	# otherwise assume file is at project root
	# first check in case it is a known directory
	if (exists $self->{dirs}{$filepath}) {
		# print "  >> found single path in object memory\n";
		return $self->{dirs}{$filepath};
	}
	# then check remotely
	my $url = sprintf "%s/files?project=%s&name=%s", $self->endpoint, $self->id, $filepath;
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
	return;
}

sub create_folder {
	my ($self, $path) = @_;
	return unless defined $path;
	$path =~ s/(\/|\\)$//; # remove trailing slash, creates problems

	# check if it exists
	if (exists $self->{dirs}{$path}) {
		return $self->{dirs}{$path};
	}

	# check for multiple directories and act appropriately
	my @dirs = File::Spec->splitdir($path);
	if (scalar @dirs > 1) {
		# walk through directory tree
		my $parent;
		my $check = 1;
		TREEWALK:
		for my $d (0..$#dirs) {
			my $dir = $dirs[$d];
			my $dirpath = $dir;
			if ($d > 0) {
				# only concatenate if there is more than one
				$dirpath = File::Spec::Unix->catdir(@dirs[0..$d]);
			}

			# start looking for this directory
			if (exists $self->{dirs}{$dirpath}) {
				# we know about this one
				$parent = $self->{dirs}{$dirpath};
				next TREEWALK;
			}
			else {
				# need to check on the platform
				if ($parent and $check) {
					my $folder = $parent->get_file_by_name($dir);
					if ($folder) {
						# this one exists on the platform
						$self->{dirs}{$dirpath} = $folder;
						$parent = $folder;
						next TREEWALK;
					}
					else {
						# we can't go looking deeper on the platform
						# proceed to make this and any subsequent folders
						$check = 0;
					}
				}

				# we need to make this folder at the current level
				my $folder;
				if ($d == 0) {
					# currently at project root level
					my $url = sprintf "%s/files", $self->endpoint;
					my $data = {
						'name' => $dirs[$d],
						'type' => 'folder',
						'project' => $self->project
					};
					my $result = $self->execute('POST', $url, undef, $data);
					if ($result) {
						$folder = Net::SB::Folder->new($self, $result);
						$self->{dirs}{$dirs[$d]} = $folder;
					}
				}
				else {
					# use current parent to make next folder
					$folder = $parent->create_folder($dirs[$d]);
				}
				# continue with this folder
				if ($folder) {
					$parent = $folder; # new parent
				}
				else {
					croak "problems making directory tree!";
				}
			}
		}
		# finished walking through the directory tree
		# parent should be the final folder we want
		return $parent;
	}
	else {
		# we are making a single new folder at the root of the project
		# check to see if it exists on platform
		my $folder =  $self->get_file_by_name($path);
		if ($folder) {
			# it exists!
			$self->{dirs}{$path} = $folder;
			return $folder;
		}
		else {
			# we need to make it
			my $url = sprintf "%s/files", $self->endpoint;
			my $data = {
				'name' => $path,
				'type' => 'folder',
				'project' => $self->project
			};
			my $result = $self->execute('POST', $url, undef, $data);
			if ($result) {
				my $folder2 = Net::SB::Folder->new($self, $result);
				$self->{dirs}{$path} = $folder2;
				return $folder2;
			}
			else {
				carp "problems making directory $path!";
			}
		}
	}
}

sub upload_file {
	my ($self, $target_filepath, $local_filepath, $overwrite) = @_;
	unless ($target_filepath) {
		carp " no target filepath provided!";
		return;
	}
	unless ($local_filepath) {
		carp " no local filepath provided!";
		return;
	}
	$overwrite ||= 0;
	if ($self->verbose) {
		printf " > upload local file '%s' to project '%s' as '%s', overwriting %s\n",
			$local_filepath, $self->name, $target_filepath, $overwrite ? 'Y' : 'N';
	}
	
	# check for directory
	my (undef, $target_dir, $target_filename) = File::Spec->splitpath($target_filepath);
	if ($target_dir) {
		if ( exists $self->{dirs}{$target_dir} ) {
			return $self->{dirs}{$target_dir}->upload_file($target_filename,
				$local_filepath, $overwrite);
		}
		else {
			my $folder = $self->create_folder($target_dir);
			return $folder->upload_file($target_filename, $local_filepath, $overwrite);
		}
	}
	else {
		# uploading into root directory
		
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
				printf "  Overwriting remote file '%s', size %d, modified on %s\n",
					$target_filename, $remote_file->size, $remote_file->modified;
			}
			else {
				printf "  Skipping remote file '%s', size %d, modified on %s\n",
					$target_filename, $remote_file->size, $remote_file->modified;
				return;
			}
		}

		# initialize upload
		my $url = sprintf "%s/upload/multipart", $self->endpoint;
		if ($overwrite) {
			$url .= '?overwrite=true';
		}
		my $data = {
			'project'   => $self->id,
			'name'      => $target_filename,
			'size'      => $file_size,
			'part_size' => $self->part_size
		};
		if ($self->verbose) {
			my $p = $self->part_size;
			printf "   >> Local file is %d bytes, will upload in %d parts of %d bytes\n",
				$file_size, 
				int( ($file_size + $p - 1) / $p ),
				$p;
		}
		my $upload = $self->execute('POST', $url, undef, $data);
		if ($upload) {
			# pass off to generic uploader function
			return $self->_upload_file($self, $local_filepath, $file_size, $upload);
		}
		else {
			carp "error uploading!";
			return;
		}
	}
}

sub bulk_upload_path {
	my $self = shift;
	croak "the sbg-upload.sh uploader is deprecated!";
}

sub bulk_upload {
	my $self = shift;
	croak "the sbg-upload.sh uploader is deprecated!";
}

sub _upload_file {
	my ($self, $parent, $file_path, $file_size, $upload) = @_;
	my $partsize = $self->part_size;
	
	# open file
	my $fh = IO::File->new($file_path);
	unless ($fh) {
		carp "cannot open '$file_path'! $OS_ERROR";
		return;
	}
	$fh->binmode;
	
	# Loop through file part uploads
	my $http = $self->new_http;
	my @part_responses;
	my $retry_count = 0;
	my $i = 1;
	ITERATOR:
	for (my $offset = 0; $offset <= $file_size; $offset += $partsize) {

		# read current part of file
		my $length;
		if ( ($offset + $partsize) > $file_size) {
			$length = $file_size - $offset;
		}
		else {
			$length = $partsize;
		}
		$fh->read(my $string, $length);
		my $content = {
			content => $string
		};

		# get upload URL
		my $data = {
			'upload_id'     => $upload->{upload_id},
			'part_number'   => $i,
		};
		my $url = sprintf "%s/upload/multipart/%s/part/%d", $self->endpoint, 
			$upload->{upload_id}, $i;
		my $upload_part = $self->execute('GET', $url, undef, $data);
		if ($upload_part) {
			# we have an upload URL
			# this does not go through SBG API, so use direct http request
			# loop through five retries
			my $n = 0;
			PART_LOOP:
			while ($n < 5) {
				if ($self->verbose) {
					printf " > Submitting %d try for part %d: %s to %s\n", $n, $i,
						$upload_part->{method}, $upload_part->{url};
				}
				# direct http request
				my $result = $http->request(
					$upload_part->{method},
					$upload_part->{url},
					$content
				);
				if ($result->{status} == 200 or $result->{status} == 201) {
					# success!!!
					if ($self->verbose) {
						printf "  > %d success for attempt $n: ETag %s\n",
							$result->{status},$result->{headers}{etag};
					}
					$result->{headers}{etag} =~ s/"//g; # it comes pre-quoted!!???
					my $part_response = {
						'part_number'   => $i,
						'response'      => {
							'headers'   => {
								'ETag'  => $result->{headers}{etag},
							}
						}
					};
					push @part_responses, $part_response;
					$n = 10;  # break out of this loop
					last PART_LOOP;
				}
				else {
					# failure
					if ($self->verbose) {
						printf "  > Failure for attempt $n: %s error %s: %s\n", 
							$result->{status}, $result->{reason}, $result->{content};
					}
					$n++;
					$retry_count++;
					sleep 2; # sleep for a bit? then try again
				}
			}
			
			# check for too many failures
			if ($n == 5) {
				carp " too many failures uploading part $i for $file_path! Canceling!";
				# send a cancel request
				my $del_url = sprintf "%s/upload/multipart/%s", $self->endpoint, 
					$upload->{upload_id};
				$self->execute('DELETE', $del_url);
				return;
			}
		}
		else {
			carp " could not request upload URL for part $i for $file_path!";
			# send a cancel request
			my $del_url = sprintf "%s/upload/multipart/%s", $self->endpoint, 
				$upload->{upload_id};
			$self->execute('DELETE', $del_url);
			return;
		}
		
		# this part succeeded
		$i++;
		
		# check 
		if (scalar @part_responses >= 25) {
			# I don't know how many of these we can keep around, but we might as well
			# not keep too many and report completed parts when we can
			my $report_url = sprintf "%s/upload/multipart/%s", $self->endpoint, 
				$upload->{upload_id};
			my $report_data = {
				'parts'         => \@part_responses,
			};
			my $response = $self->execute('POST', $report_url, undef, $report_data);
			if ($response) {
				@part_responses = ();
			}
		}
	}
	
	# final report of completed parts
	if (@part_responses) {
		my $report_url = sprintf "%s/upload/multipart/%s", $self->endpoint, 
			$upload->{upload_id};
		my $report_data = {
			'parts'         => \@part_responses,
		};
		my $response = $self->execute('POST', $report_url, undef, $report_data);
	}
	
	# finalize upload
	my $final_url = sprintf "%s/upload/multipart/%s/complete", $self->endpoint, 
			$upload->{upload_id};
	my $response = $self->execute('POST', $final_url);
	if ($response) {
		return Net::SB::File->new($parent, $response);
	}
	else {
		print " ! failed to complete upload?? Try again\n";
		sleep 10;
		$response = $self->execute('POST', $final_url);
		if ($response) {
			return Net::SB::File->new($parent, $response);
		}
		else {
			print " ! failed to complete upload!\n";
			return;
		}
	}
}


1;

__END__

=head1 Net::SB::Project

Class object representing a Project on the Seven Bridges platform.

See Net::SB documentation for details.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  


