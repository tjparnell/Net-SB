package Net::SB::Member;

use warnings;
use strict;
use Carp;
use base 'Net::SB';

our $VERSION = Net::SB->VERSION;

sub new {
	my ($class, $parent, $result) = @_;
	if (ref $class) {
		$class = ref $class;
	}

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

=head1 Net::SB::Member - a Member on the Seven Bridges platform

=head1 DESCRIPTION

This represents a member on the Seven Bridges platform. It may be generated 
by listing methods from either a L<Net::SB::Project>, L<Net::SB::Division>,
or L<Net::SB::Team> object. 

* L<Net::SB::Division/list_members> 

* L<Net::SB::Project/list_members> 

* L<Net::SB::Project/add_member> 

* L<Net::SB::Team/list_members> 

* L<Net::SB::Team/add_member> 

B<NOTE> Due to slight variations in the Seven Bridges API and where the 
member object was generated, the metadata and identifiers for the member may 
vary. Best attempts are made to normalize these C<id> and C<username> values,
but in general the information is highly context dependent. Further, additional 
information can only be obtained through the API for you, the current user, and 
not other members. 

This is generally a read-only object. Modifications to permissions may be done 
though the Project object.

=head1 METHODS

=over 4

=item new

Generally this object should only be initialized from another object and not 
directly by end-users. It requires returned JSON data from the Seven Bridges 
API and parent object information.

=item id

Returns the user ID, which is usually C<division/shortname>.

=item href

Returns the URL for this member.

=item username

Returns the short user name of the user.

=item email

Returns the associated email address of the user as a string.

=item name

If available, returns a string as "First Last". Otherwise returns the 
short user name.

=item first_name

Returns first name of user. May not be present.

=item last_name

Returns the last name. May not be present.

=item type

Returns C<ADMIN> or C<USER> depending on context and the 
origin of the member object. 

=item role

Returns C<MEMBER> or C<ADMIN> value, usually in the context of 
membership in a Project. This may not be present in all cases.

=item read

Returns the boolean value for the Read permission of the user, usually for a Project.
For most users, this is true.

=item copy

Returns the boolean value for the Copy permission of the user, usually for a Project. 
For most users, this is true.

=item write

Returns the boolean value for the Write permission of the user, usually for a Project.

=item exec

Returns the boolean value for the task Execution permission of the user, usually for a Project.

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


