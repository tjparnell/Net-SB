package Net::SB::Division;

use warnings;
use strict;
use Carp;
use File::Spec;
use base 'Net::SB';
use Net::SB::Project;
use Net::SB::Member;
use Net::SB::Team;
use Net::SB::Volume;

our $VERSION = Net::SB->VERSION;

sub new {
	my $class = shift;
	if (ref $class) {
		$class = ref $class;
	}

	my %args = @_;
	my $self = {
		div     => $args{div} || undef,   # 'hci-bioinformatics-shared-reso'
		name    => $args{name} || undef,  # 'HCI Bioinformatics Shared Resource'
		href    => $args{href} || undef,  # https://api.sbgenomics.com/v2/divisions/hci-bioinformatics-shared-reso
		cred    => $args{cred} || undef,  # ~/.sevenbridges/credentials
		token   => $args{token} || undef, # hexadecimal number
		verb    => $args{verbose},        # 0 or 1
		end     => $args{end},            # https://api.sbgenomics.com/v2
		partsz  => $args{partsz},
		bulksz  => $args{bulksz},
		napval  => $args{napval},
	};

	return bless $self, $class;
}

sub id {
	return shift->{div};
}

sub name {
	my $self = shift;
	if (not defined $self->{name}) {
		my $url = sprintf "%s/divisions/%s", $self->endpoint, $self->id;
		my $options = {
			'cache-control' => 'no-cache',
			'x-sbg-advance-access' => 'advance',
		};
		my $result = $self->execute('GET', $url, $options);
		$self->{name} = $result->{name};
	}
	return $self->{name};
}

sub href {
	my $self = shift;
	unless (defined $self->{href}) {
		# make it up
		$self->{href} = sprintf "%s/divisions/%s", $self->endpoint, $self->id;
	}
	return $self->{href};
}


*projects = \&list_projects;

sub list_projects {
	my $self = shift;
	if (not exists $self->{projects}) {
		my @results = $self->execute('GET', (sprintf "%s/projects", $self->endpoint));
		my @projects = map { Net::SB::Project->new($self, $_) } @results;
		$self->{projects} = \@projects;
	}
	return wantarray ? @{ $self->{projects} } : $self->{projects};
}

sub create_project {
	my $self = shift;
	my %options = @_;
	unless (exists $options{name}) {
		carp "A new project requires a name!";
		return;
	}
	$options{billing_group} = $self->billing_group; # this may need to be requested

	# execute
	my $result = $self->execute('POST', sprintf("%s/projects", $self->endpoint),
		undef, \%options);
	if ( ref($result) eq 'HASH' ) {
		return Net::SB::Project->new($self, $result);
	}
	else {
		return undef;
	}
}

sub get_project {
	my $self = shift;
	my $project = shift;
	unless ($project) {
		carp "project short name must be provided!";
		return;
	}

	# execute
	my $url = sprintf "%s/projects/%s/%s", $self->endpoint, $self->id, $project;
	my $result = $self->execute('GET', $url);
	if ( ref($result) eq 'HASH' ) {
		return Net::SB::Project->new($self, $result);
	}
	else {
		return undef;
	}
}

sub list_members {
	my $self = shift;
	if (not exists $self->{members}) {
		my $url = sprintf "%s/users?division=%s", $self->endpoint, $self->id;
		my @results = $self->execute('GET', $url);
		my @members =
			map { Net::SB::Member->new($self, $_) }
			grep { ref eq 'HASH' } @results;
		$self->{members} = \@members;
	}
	return wantarray ? @{ $self->{members} } : $self->{members};
}

sub billing_group {
	my $self = shift;
	if (not exists $self->{billing}) {
		my @results = $self->execute('GET', (sprintf "%s/billing/groups", $self->endpoint));
		if (scalar @results > 1) {
			printf "More than one billing group associated with division! Using first one\n";
		}
		$self->{billing} = $results[0]->{id};
	}
	return $self->{billing};
}

sub list_teams {
	my $self = shift;
	my $h = {'x-sbg-advance-access' => 'advance'};
	my $url = sprintf "%s/teams?division=%s&_all=true", $self->endpoint, $self->division;
	my @results = $self->execute('GET', $url, $h);
	my @teams =
		map { Net::SB::Team->new($self, $_) }
		grep { ref eq 'HASH' } @results;
	return wantarray ? @teams : \@teams;
}

sub create_team {
	my $self = shift;
	my $name = shift || undef;
	unless ($name) {
		carp "A new team requires a name!";
		return;
	}
	my $data = {
		name     => $name,
		division => $self->division,
	};

	# execute
	my $h = {'x-sbg-advance-access' => 'advance'};
	my $result = $self->execute('POST', sprintf("%s/teams", $self->endpoint), $h, $data);
	if ( ref($result) eq 'HASH' ) {
		return Net::SB::Team->new($self, $result);
	}
	else {
		return undef;
	}
}

sub bulk_delete {
	my $self = shift;
	# get the list of files
	my @files;
	if (scalar @_ == 1 and ref $_[0] eq 'ARRAY') {
		my $a = shift @_;
		@files = @{$a};
	}
	elsif (scalar @_ > 1) {
		@files = @_;
	}
	else {
		carp "Must pass array (reference) of files!";
		return;
	}

	my $url = sprintf "%s/bulk/files/delete", $self->endpoint;
	my $limit = $self->bulk_size;
	my @outs;
	my @folders;
	my %lookup; # lookup of ID to array index

	# process through the list
	my $count = my $number = scalar @files;
	my $i = 0;
	while ($count) {
		# collect file IDs
		my @ids; # array of file IDs 
		while ($i < $number) {
			if ($files[$i]->type eq 'folder') {
				# skip folders, but remember them later
				push @folders, $files[$i];
			}
			elsif ($files[$i]->type eq 'file') {
				my $id = $files[$i]->id;
				push @ids, $id;
				$lookup{$id} = $i;
			}
			$i++;
			$count--;
			last if scalar(@ids) == $limit;
		}
		# request
		if (@ids) {
			my $data = {
				file_ids => \@ids,
			};
			my $results = $self->execute('POST', $url, undef, $data);
			foreach my $r (@{$results}) {
				if (exists $r->{error}) {
					# problem
					my $id = $r->{id} || undef;
					my $j = $lookup{$id};
					push @outs, sprintf "%s: %s %s", $r->{error}{code},
						$r->{error}{message}, $files[$j]->pathname || undef;
				}
				else {
					# evidently success
					my $id = $r->{resource}{id};
					my $j = $lookup{$id};
					push @outs, sprintf "deleted %s", $files[$j]->pathname;
				}
			}
		}
	}

	# check any folders
	if (@folders) {
		# first resort the folders, first by reverse depth then name
		my @sortfolders =
			map { $_->[0] }
			sort { $b->[1] <=> $a->[1] or $a->[2] cmp $b->[2] }
			map { [ $_, scalar(split /\//, $_->path), $_->path ] } @folders;

		# then delete individually, can't do it in bulk because of nesting
		while (@sortfolders) {
			my $folder = shift @sortfolders;
			my $contents = $folder->list_contents;
			if (scalar @{$contents} == 0) {
				my $result = $folder->delete;
				if ($result
					and ref($result) eq 'HASH'
					and exists $result->{error}{code}
				) {
					# an error
					push @outs, sprintf "%s: %s %s", $result->{error}{code},
						$result->{error}{message}, $folder->path || undef;
				}
				else {
					# likely success
					push @outs, sprintf "deleted empty folder %s", $folder->path;
				}
			}
		}
	}
	return wantarray ? @outs : \@outs;
}

sub bulk_get_file_details {
	my $self = shift;

	# get the list of files
	my @files;
	if (scalar @_ == 1 and ref $_[0] eq 'ARRAY') {
		my $a = shift @_;
		@files = @{$a};
	}
	elsif (scalar @_ > 1) {
		@files = @_;
	}
	else {
		carp "Must pass array (reference) of files!";
		return;
	}

	my $url = sprintf "%s/bulk/files/get", $self->endpoint;
	my $limit = $self->bulk_size;
	my %lookup; # lookup of ID to array index

	# process through the list
	my $count = my $number = scalar @files;
	my $i = 0;
	my $success = 0;
	while ($count) {
		# collect file IDs
		my @ids; # array of file IDs 
		while ($i < $number) {
			my $f = $files[$i];
			if ($f->type eq 'file') {
				my $id = $f->id;
				push @ids, $id;
				$lookup{$id} = $f;
			} # we skip any folder that may exist
			$i++;
			$count--;
			last if scalar(@ids) == $limit;
		}
		# request
		if (@ids) {
			my $data = {
				file_ids => \@ids,
			};
			my $results = $self->execute('POST', $url, undef, $data);
			foreach my $r (@{$results}) {
				if (exists $r->{error}) {
					# print some kind of error message????
				}
				else {
					my $id = $r->{resource}{id};
					my $file = $lookup{$id};
					# pass the results to the file object to integrate details
					# into the existing object
					$file->get_details( $r->{resource} );
					$success++;
				}
			}
		}
	}
	return $success;
}

sub submit_multiple_file_copy {
	my ($self, $files) = @_;
	unless (ref $files eq 'ARRAY') {
		carp "must pass an array reference of File objects!";
		return;
	}
	
	# collect the items to copy
	my $items = $self->_process_multiple_files($files);
	unless ($items) {
		carp "problem parsing the list of files";
		return;
	}
	
	# execute
	my $url = sprintf "%s/async/files/copy", $self->endpoint;
	my $data = {
		'items' => $items,
	};
	return $self->execute('POST', $url, undef, $data);
}

sub submit_multiple_file_move {
	my ($self, $files) = @_;
	unless (ref $files eq 'ARRAY') {
		carp "must pass an array reference of File objects!";
		return;
	}
	
	# collect the items to copy
	my $items = $self->_process_multiple_files($files);
	
	# execute
	my $url = sprintf "%s/async/files/move", $self->endpoint;
	my $data = {
		'items' => $items,
	};
	return $self->execute('POST', $url, undef, $data);
}

sub _process_multiple_files {
	my ($self, $files) = @_;
	my @data;
	foreach my $f ( @{ $files } ) {
		my $item = {};
		# source
		if (ref $f->[0] eq 'Net::SB::File') {
			$item->{file} = $f->[0]->id;
		}
		elsif (ref $f->[0] eq 'Net::SB::Folder') {
			$item->{file} = $f->[0]->id;
		}
		else {
			carp " Source is not a Net::SB::File or Net::SB::Folder object!";
			return;
		}
		# destination
		if (ref $f->[1] eq 'Net::SB::Project') {
			$item->{project} = $f->[1]->id;
		}
		elsif (ref $f->[1] eq 'Net::SB::Folder') {
			$item->{parent} = $f->[1]->id;
		}
		else {
			carp " Destination is not a Net::SB::Folder or Net::SB::Project object!";
			return;
		}
		if (defined $f->[2]) {
			$item->{name} = $f->[2];
		}
		push @data, $item;
	}
	return \@data;
}

sub get_async_job_result {
	my ($self, $result) = @_;
	my $url = sprintf "%s/async/files/%s/%s", $self->endpoint, lc $result->{type},
		$result->{id};
	return $self->execute('GET', $url);
}

sub watch_async_job {
	my ($self, $result) = @_;

	my $url = sprintf "%s/async/files/%s/%s", $self->endpoint, lc $result->{type},
		$result->{id};
	my $nap_time = $self->sleep_value;
	while (1) {
		my $progress = $self->execute('GET', $url);
		printf " > %s %s: %s, %d completed, %d failed, %d total\n",
			$progress->{type},
			$progress->{id},
			$progress->{'state'},
			$progress->{completed_files},
			$progress->{failed_files},
			$progress->{total_files};
		# continue or not
		if ($progress->{'state'} eq 'FINISHED') {
			return $progress;
		}
		elsif ($progress->{'state'} =~ /submitted | resolving | running/xi) {
			sleep $nap_time;
		}
		else {
			carp sprintf( "unrecognized state %s!", $progress->{'state'} );
			return;
		}
	}
}

sub get_async_job_files {
	my ($self, $result, $project) = @_;
	unless (ref $result eq 'HASH') {
		carp " must pass a result hash reference";
		return;
	}
	unless (ref $project eq 'Net::SB::Project') {
		carp " must pass a Net::SB::Project object";
		return;
	}
	my @files;
	foreach my $f ( @{ $result->{result} } ) {
		push @files, Net::SB::File->new($project, $f);
	}
	$self->bulk_get_file_details(\@files);
	return wantarray ? @files : \@files;
}

sub list_volumes {
	my $self = shift;
	my $url = sprintf "%s/storage/volumes", $self->endpoint;
	my $headers = {
		'x-sbg-advance-access' => 'advance'
	};
	my @results = $self->execute('GET', $url, $headers);
	if (@results) {
		my @volumes;
		foreach my $r (@results) {
			next unless ref($r) eq 'HASH';
			push @volumes, Net::SB::Volume->new($self, $r);
		}
		return wantarray ? @volumes : \@volumes;
	}
	else {
		return;
	}
}

sub get_volume {
	my ($self, $name) = @_;
	my $vols = $self->list_volumes;
	foreach my $v (@{$vols}) {
		if ($v->name eq $name) {
			return $v;
		}
	}
	return;
}

sub attach_volume {
	my $self = shift;
	return Net::SB::Volume->new($self, @_);
}

1;

__END__

=head1 Net::SB::Division - A division on the Seven Bridges platform

=head1 DESCRIPTION

This represents a laboratory or user division which contains one or 
more projects. This is essentially the starting point to projects.

=head1 METHODS

=over 4

=item new

Generally this object should only be initialized from the L<Net::SB> 
new() function, and not directly by end-users.

=item id

The identifier, or short name, for this division.

=item href

Returns the URL for this division.

=item name

The name of the division. May be different text from the short name identifier.

=item list_projects

Return list of available projects as L<Net::SB::Project> objects within current division.
Restricted to those that the current user can see. 

=item create_project

Make new project. Returns L<Net::SB::Project> object.
Pass array of information.

    name        => $name,
    description => $description, # can be Markdown

=item get_project

Given a short name identifier, return a L<Net::SB::Project> object for the project.

=item list_members

Returns an array or array reference with a list of L<Net::SB::Members> objects 
for each member in the division.

=item billing_group

Returns the C<ID> of the C<billing_group>. 

=item list_teams

Returns a list of all the teams in the division, not necessarily those to which 
the user is a member. Returns L<Net::SB::Team> objects. 

=item create_team

Pass the name of a new team to create. A L<Net::SB::Team> object will be returned
to which members will need to be added.

=back

=head2 Bulk file functions

These methods submit jobs to the Seven Bridges platforms for work on a list 
of file objects in a single, or limited, number of API queries, as opposed to 
submitting an API query repeatedly for each and every file. Since these work 
on file objects through their unique IDs, they are not necessarily limited to
a single project, and instead can work across multiple projects.

=over 4

=item bulk_delete

Pass an array or array reference of L<Net::SB::File> file objects. These 
will be deleted via a bulk API call. Returns an array of message strings 
of success or failure which can be printed to a user.

=item bulk_get_file_details

Pass an array or array reference of L<Net::SB::File> file objects. A bulk API 
call will be made to collect additional file details, and the file objects 
will be updated with the additional details. Useful for efficiently getting 
metadata or file sizes. The number of successful files updated will be returned.

=item submit_multiple_file_copy

=item submit_multiple_file_move

These two methods are similar in usage and methodology. They both submit an
asynchronous job to either copy or move a list of files from source to
destination. A job identifier is returned upon submission, which can then be 
queried at a later time for status and results. These methods are called by 
passing an ARRAY reference for each file.

    my $result = $Sb->submit_multiple_file_copy( 
        [
            [$source1, $destination],
            [$source2, $destination, $new_name],
            # repeat ad nauseum
        ]
    );
    
In the example, each C<$source> is either a L<Net::SB::File> or
L<Net::SB::Folder> object, and each C<$destination> is either a
L<Net::SB::Project> or L<Net::SB::Folder> object. Source folders will preserve
underlying folder structure. Destinations can be mixed and do not need to be the
same, nor even in the same project in the case of folders. If desired, a new
file name may be provided as a SCALAR string, perhaps to avoid naming
collisions.

The returned result is HASH reference of status and results. This can be provided
to the following methods. See 
L<Async Copy|https://docs.sevenbridges.com/reference/copy-multiple-files> or 
L<Async Move|https://docs.sevenbridges.com/reference/move-multiple-files-or-folders>.

=item get_async_job_result

Pass the C<$result> hash from a submitted async job. This project returns the 
results of the asynchronous job.

=item watch_async_job

Pass the C<$result> hash from a submitted async job. B<WARNING> This project
enters an infinite loop and prints an updated status message every cycle while
the job is running. The loop sleeps for the number of seconds specified in
L<Net::SB/sleep_value>. The loop breaks if the returned status code is 
C<FINISHED> or an unrecognized status code is given. The final result is 
returned when the loop breaks.

=item get_async_job_files

Pass the C<$result> hash from a completed async job. It will parse the resulting 
file IDs and return an array reference of L<Net::SB::File> objects. Note that 
complete directory paths may not be included.

=back

=head2 Volume functions

These functions pertain to mounted volumes within a Seven Bridges division.

=over 4

=item list_volumes

Returns a list of L<Net::SB::Volume> objects representing any mounted remote 
volume, such as an AWS bucket, attached to the division.

=item get_volume

Pass the name of a known volume and the corresponding L<Net::SB::Volume> object
will be returned, if available. A little faster than manually listing and 
searching for the volume of interest. 

=item attach_volume

Convenience method for attaching a new volume by passing an array of key =E<gt> 
value pairs of connection values. Currently this only support AWS S3 buckets. 
Values include the following:

=over 4

=item type 

Provide either C<s3> or C<gcs> for AWS buckets or Google Cloud Storage.

=item bucket

The name of the bucket

=item access

Provide either C<RO> or C<RW> for read-only or read-write access. Default is "RO".

=item access_key_id

The S3 access key identifier.

=item secret_access_key

The S3 secret access key identifier.

=back

If successful it will return a L<Net::SB::Volume> object.

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



