package Net::SB::Project;

use warnings;
use strict;
use Carp;
use base 'Net::SB';
use Net::SB::Member;

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
	# this may or may not be present, depending on how details were obtained
	# if it was just created, we would have it, but not if we just listed from division
	# could force to fetch more details
	# also possible to update description if need be, but see update() below
	return $self->{description} || undef;
}

sub root_folder {
	my $self = shift;
	return $self->{root_folder};
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

	my $self = shift;
		}
	}
}

	my $self = shift;
	
	
}

sub bulk_upload_path {
	my $self = shift;
	croak "the sbg-upload.sh uploader is deprecated!";
}

sub bulk_upload {
	my $self = shift;
	croak "the sbg-upload.sh uploader is deprecated!";
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


