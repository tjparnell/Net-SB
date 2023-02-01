package Net::SB::Member;

use warnings;
use strict;
use Carp;
use base 'Net::SB';

our $VERSION = Net::SB->VERSION;

sub new {
	my ($class, $parent, $result) = @_;

	# create object based on the given result
	# this is tricky, because the results will vary with different keys depending 
	# on whether this is was called from a division or a project - sigh
	# this is from a project
	#   {
    #     'type' => 'USER',
    #     'href' => 'https://api.sbgenomics.com/v2/projects/division/playground/members/division/tjparnell',
    #     'id' => 'division/tjparnell',
    #     'permissions' => {
    #                        'read' => 1,
    #                        'execute' => 1,
    #                        'copy' => 1,
    #                        'write' => 1,
    #                        'admin' => 1
    #                      },
    #     'email' => 'xxxx.xxx@xxx.xxx.edu',
    #     'username' => 'division/tjparnell'
    #   },
	unless (defined $result and ref($result) eq 'HASH') {
		confess "Must call new() with a parsed JSON member result HASH!";
	}
	my $self = $result;

	# minimum data
	unless (exists $self->{href}) {
		confess "Missing href! Is this a SB result hash!?";
	}
	$self->{id}       ||= q();
	$self->{type}     ||= 'USER';
	$self->{username} ||= q();
	$self->{email}    ||= q();
	
	# add division object
	if (ref $parent eq 'Net::SB::Division') {
		$self->{divobj} = $parent; # 
	}
	else {
		$self->{divobj} = $parent->{divobj};
	}
	# clean up some stuff due to inconsistencies in the API and the source of the result
	# for example username and id
	if ( $self->{username} =~ m/^( [a-z0-9\-]+ ) \/ ( [\w\-\.]+ ) $/x ) {
		my $div = $1;
		my $name = $2;
		$self->{id} = $self->{username}; # id is division/shortname
		$self->{username} = $name;       # username is shortname
	}
	elsif ( $self->{username} ) {
		$self->{id} = sprintf "%s/%s", $parent->division, $self->{username};
	}

	return bless $self, $class;
}

sub id {
	my $self = shift;
	if (exists $self->{id} and defined $self->{id}) {
		return $self->{id};
	}
	elsif (exists $self->{username} and defined $self->{username}) {
		# generate what should be the ID
		return $self->{username};
	}
	else {
		return undef;
	}
}

sub name {
	my $self = shift;
	if (exists $self->{first_name} and exists $self->{last_name}) {
		return (sprintf "%s %s", $self->{first_name}, $self->{last_name});
	}
	else {
		return $self->username;
	}
}

sub username {
	# I think this should always be present
	my $self = shift;
	if (exists $self->{username} and defined $self->{username}) {
		return $self->{username};
	}
	elsif (exists $self->{id} and $self->{username} =~ m/^ [a-z0-9\-]+ \/ ( [\w\-]+ ) $/x) {
		# extract it from the ID
		return $1;
	}
	else {
		return undef;
	}
}

sub email {
	my $self = shift;
	return $self->{email} || undef; # this should always be present
}

sub first_name {
	my $self = shift;
	if (exists $self->{first_name}) {
		return $self->{first_name};
	}
	else {
		return undef;
	}
}

sub last_name {
	my $self = shift;
	if (exists $self->{last_name}) {
		return $self->{last_name};
	}
	else {
		return undef;
	}
}

sub type {
	# project attribute
	my $self = shift;
	return $self->{type} || undef;
}

sub role {
	# division attribute
	my $self = shift;
	if (exists $self->{role}) {
		return $self->{role};
	}
	else {
		return undef;
	}
}

sub copy {
	# project attribute
	my $self = shift;
	if (exists $self->{permissions}) {
		return $self->{permissions}{copy} || undef;
	}
	else {
		return undef;
	}
}

sub write {
	# project attribute
	my $self = shift;
	if (exists $self->{permissions}) {
		return $self->{permissions}{write} || undef;
	}
	else {
		return undef;
	}
}

sub read {
	# project attribute
	my $self = shift;
	if (exists $self->{permissions}) {
		return $self->{permissions}{read} || undef;
	}
	else {
		return undef;
	}
}

sub exec {
	# project attribute
	my $self = shift;
	if (exists $self->{permissions}) {
		return $self->{permissions}{exec} || undef;
	}
	else {
		return undef;
	}
}

sub href {
	# attribute of both, but have different URLs
	my $self = shift;
	return $self->{href};
}

1;

__END__

=head1 Net::SB::Member

Class object representing a Member on the Seven Bridges platform.

See Net::SB documentation for details.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  


