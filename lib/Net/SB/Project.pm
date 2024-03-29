package Net::SB::Project;

use warnings;
use strict;
use English qw(-no_match_vars);
use Carp;
use IO::File;
use File::Spec;
use File::Spec::Unix;
use base 'Net::SB';
use Net::SB::Member;
use Net::SB::File;
use Net::SB::Folder;
use Net::SB::Task;

our $VERSION = Net::SB->VERSION;

sub new {
	my ($class, $parent, $result) = @_;
	if (ref $class) {
		$class = ref $class;
	}

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

	# minimum data
	unless (exists $self->{href} and exists $self->{id}) {
		confess "Missing critical href and/or id keys!";
	}
	$self->{name} ||= q();    # this should never be null
	
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
		'href'      => sprintf("%s/users/%s", $self->{href}, $id),
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

	# execute
	my $result = $self->execute('PATCH', $self->href, undef, \%data);

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
		my @members =
			map { Net::SB::Member->new($self, $_) }
			grep { ref eq 'HASH' } @results;
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
	my $url = sprintf "%s/members/%s/permissions", $self->href, $username;
	my $result = $self->execute('PATCH', $url, undef, \%permissions);
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
	my $limit = shift || 0;
	$limit = int $limit;
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
			my $contents = $self->_recurse($item, $limit);
			if ($contents and scalar @{ $contents } ) {
				push @files, @{ $contents };
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
	my @files;
	if ($limit) {
		my @dirs = File::Spec::Unix->splitdir($folder->path);
		return if (@dirs and scalar @dirs >= int $limit);
	}
	my $contents = $folder->list_contents;
	foreach my $item (@{$contents}) {
		if ($item->type eq 'file') {
			# keep the file
			push @files, $item;
		}
		else {
			# recurse into this subdirectory
			push @files, $item;
			my $contents2 = $self->_recurse($item, $limit);
			if ($contents2 and scalar @{ $contents2 } ) {
				push @files, @{ $contents2 };
			}
		}
	}
	return \@files;
}

sub list_files_by_task {
	my $self   = shift;
	my $task   = shift || undef;
	my $folder = shift || undef;
	return unless $task;
	
	# get task object
	my $task_obj;
	if (ref($task) eq 'Net::SB::Task') {
		$task_obj = $task;
	}
	else {
		$task_obj = $self->get_task($task);
	}
	unless ($task_obj) {
		carp " unable to find Task '$task' in the project";
		return;
	}
	
	# get folder
	my $folder_obj;
	if ( $folder and ref($folder) eq 'Net::SB::Folder' ) {
		$folder_obj = $folder;
	}
	elsif ( $folder ) {
		$folder_obj = $self->get_file_by_name($folder);
		unless ($folder_obj and $folder_obj->type eq 'folder') {
			carp " unable to find folder '$folder' in the project";
			return;
		}
	}

	# recurse by batch or not
	my @files;
	if ( $task_obj->batch ) {

		# we need to get the child tasks first
		my $children = $task_obj->get_children;
		if ( $children and ref($children) eq 'ARRAY' ) {
			foreach my $child ( @{ $children } ) {
				my $kid_files = $self->list_files_by_task( $child, $folder_obj );
				if ( $kid_files and ref($kid_files) eq 'ARRAY' ) {
					push @files, @{ $kid_files };
				}
			}
		}
	}
	else {

		# regular task
		my $url = sprintf "%s/files?origin.task=%s&offset=0&limit=100", 
			$self->endpoint, $task_obj->id;
		if ($folder_obj) {
			$url .= sprintf "&parent=%s", $folder_obj->id;
		}
		else {
			$url .= sprintf "&project=%s", $self->id;
		}
		my @results = $self->execute('GET', $url);

		# process into file and folder objects
		# I don't think folders are necessarily expected, but leave this anyway
		foreach my $f (@results) {
			my $type = $f->{type};
			if ($type eq 'file') {
				push @files, Net::SB::File->new($self, $f);
			}
			elsif ($type eq 'folder') {
				my $folder2 = Net::SB::Folder->new($self, $f);
				push @files, $folder2;
			}
			else {
				carp sprintf "unknown object type '$type' for %s", $f->{name};
			}
		}
	}
	
	return wantarray ? @files : \@files;
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
	my $url = sprintf "%s/files?project=%s&name=%s", $self->endpoint, $self->id,
		$self->_encode($filepath);
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

sub list_tasks {
	my $self = shift;
	my $url = sprintf "%s/tasks?project=%s", $self->endpoint, $self->id;
	my @results = $self->execute('GET', $url);
	my @tasks;
	if (@results) {
		foreach (@results) {
			my $t = Net::SB::Task->new($self, $_);
			if ($t) {
				push @tasks, $t;
			}
		}
	}
	return wantarray ? @tasks : \@tasks;
}

sub get_task {
	my $self = shift;
	my $id   = shift || q();
	unless ($id and $id =~ /^[\w\-]+$/) {
		return;
	}
	my $url = sprintf "%s/tasks/%s", $self->endpoint, $id;
	my $result = $self->execute('GET', $url);
	if ( $result ) {
		return Net::SB::Task->new($self, $result);
	}
	return;
}

sub delete {
	my $self = shift;
	return $self->execute('DELETE', $self->href);
}


1;

__END__

=head1 Net::SB::Project - a Project on the Seven Bridges platform

=head1 DESCRIPTION

This represents a project on the Seven Bridges platform. It may be generated 
from the following L<Net::SB::Division> methods:

* L<Net::SB::Division/list_projects> 

* L<Net::SB::Division/get_project>

* L<Net::SB::Division/create_project>

=head1 METHODS

=over 4

=item new

Generally this object should only be initialized from a L<Net::SB::Division> 
object and not directly by end-users. It requires returned JSON data from the 
Seven Bridges API and parent object information.

=item id

The identifier, or short name, of the project, such C<RFranklin/my-project>.

=item project

Same as L<id>.

=item href

Returns the URL for this project.

=item name

The human name of the project, which may be different text from the short identifier. 

=item description

Gets the description of the project. Can be set by passing text to L<update>.

=item root_folder

Returns a L<Net::SB::Folder> object representing the root folder of the project.

=item billing_group

Returns the billing group id.

=item created_by

Returns a L<Net::SB::Member> object of the member who created the project.
Note that extremely limited information is available from this member object,
basically nothing beyond an identifier. If additional information is needed, 
one should use L<list_members> and match up that way.

=item created_on

Returns the C<created_on> value, such C<2019-06-18T03:40:09Z>.

=item modified_on

Returns the C<modified_on> value.

=item location

Returns the C<location> value of where the file is hosted, such as C<us-east-1>.

=item permissions

Returns a hash of the permissions that the current user (you) have with the project.

=item update

Pass an array of key =E<gt> value pairs of information to update the project.
Returns 1 if successful. Object metadata is updated.

    name        => $new_name,
    description => $text, # can be Markdown

=item list_members

Returns list of L<Net::SB::Member> objects who are members of the current project.

=item add_member

Pass the member identifier, member's email address on the platform, 
an L<Net::SB::Member> object, or an L<Net::SB::Team> object to 
add to the project. Optionally, pass additional key =E<gt> value pairs to 
set permissions. Default permissions are C<read> and C<copy> are C<TRUE>, 
and C<write>, C<execute>, and C<admin> are C<FALSE>.

=item modify_member_permission

Pass the L<Net::SB::Member> (or L<Net::SB::Team>) object and an array of key =E<gt> value 
pairs to change the member's permissions for this project. Possible keys 
include C<read>, C<copy>, C<write>, C<execute>, and C<admin>. Possible values 
include C<TRUE> and C<FALSE>.

=item list_contents

List all files and folders at the root level of the project. Does not recurse.
Returns an array or array reference of L<Net::SB::File> and L<Net::SB::Folder> 
objects as appropriate.

=item recursive_list

=item recursive_list($regex)

=item recursive_list( $regex, $limit )

Recursively list all file and folders within the project, recursing into folders
as necessary until everything is found. Optionally pass a Perl regular
expression as an argument for filtering the found objects based on their
pathname, i.e. folders plus filename. Returns an array or array reference of
L<Net::SB::File> and L<Net::SB::Folder> objects as appropriate. 

An integer may optionally be provided as a second argument to limit the recursive 
limit relative to the starting point, where 1 is the current folder. If a filter 
is not needed, pass an empty or undefined value as the first argument.

=item list_files_by_task($task_id)

=item list_files_by_task( $task_id, $folder )

List all the files generated by an analysis task. Provide the task identifier 
(a hexadecimal identifier) or a L<Net::SB::Task> object. If the files have 
been (subsequently) moved to a folder (by default, all generated task files are 
deposited in the root folder), then optionally provide either the folder path 
or the L<Net::SB::Folder> object. 

Returns an array or array reference of L<Net::SB::File>
and L<Net::SB::Folder> objects as appropriate.

=item get_file_by_name($filepath)

Despite the name, this works equally with both files and folders.
Provide a file path, either a filename in the root folder, or with a folder path. 
The file is searched for by recursing as necessary into each folder. If the file 
(or folder) is found, it is returned as an appropriate object.

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

=item list_tasks

Return an array or array reference of L<Net::SB::Task> objects representing 
analysis tasks executed in this Project.

=item get_task($id)

Retrieves a specific analysis task given the unique id number. Returns a 
L<Net::SB::Task> object if found.

=item delete

Delete the project! B<All files therein will be deleted!!!>. Requires
admin privileges on the project.  

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

=item part_size

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


