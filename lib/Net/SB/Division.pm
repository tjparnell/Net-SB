package Net::SB::Division;

use warnings;
use strict;
use Carp;
use IO::File;
use File::Spec;
use base 'Net::SB';
use Net::SB::Project;
use Net::SB::Member;
use Net::SB::Team;
use Net::SB::Volume;

sub new {
	my $class = shift;
	if (ref($class)) {
		$class = ref($class);
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
	return $result ? Net::SB::Project->new($self, $result) : undef;
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
	return $result ? Net::SB::Project->new($self, $result) : undef;
}

sub list_members {
	my $self = shift;
	if (not exists $self->{members}) {
		my $url = sprintf "%s/users?division=%s", $self->endpoint, $self->id;
		my @results = $self->execute('GET', $url);
		my @members = map { Net::SB::Member->new($self, $_) } @results;
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
	my @teams = map { Net::SB::Team->new($self, $_) } @results;
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
	return $result ? Net::SB::Team->new($self, $result) : undef;
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

=head1 Net::SB::Division

Class object representing a Division on the Seven Bridges platform.

See Net::SB documentation for details.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  



