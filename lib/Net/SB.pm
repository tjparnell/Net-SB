package Net::SB;

use warnings;
use strict;
use Carp;
use HTTP::Tiny;
use JSON::PP;	# this is reliably installed, XS is not
				# XS would be better performance, but we're not doing anything complicated
use Net::SB::Division;

our $VERSION = 0.2;


# Initialize 
BEGIN {
	# this is only for more recent versions, so disabled
	# it will have to fail later if SSL stuff isn't available
	unless (HTTP::Tiny->can_ssl) {
		die "No SSL support installed. Please install Net::SSLeay and IO::Socket::SSL";
	}
}
my $http = HTTP::Tiny->new();

1;



sub new {
	my $class = shift;
	if (ref($class)) {
		$class = ref($class);
	}
	
	# arguments
	my %args = @_;
	my $division  = $args{div} || $args{division} || $args{profile} || undef;
	my $cred_path = $args{cred} || $args{cred_path} || $args{credentials} || undef;
	my $token     = $args{token} || undef;
	my $verb      = $args{verbose} || $args{verb} || 0;
	my $partsize  = $args{partsize} || 32 * 1024 * 1024; # 32 MB
	my $bulksize  = $args{bulksize} || 100;
	my $sleep_val = $args{sleepvalue} || 60;
	my $endpoint  = $args{endpoint} || 'https://api.sbgenomics.com/v2/'; # default
	
	# check for credentials file
	if (defined $cred_path) {
		unless (-e $cred_path and -r _ ) {
			croak "bad credential file path! File unreadable or doesn't exist";
		}
	}
	else {
		my $f = File::Spec->catfile($ENV{HOME}, '.sevenbridges', 'credentials');
		if (-e $f and -r _ ) {
			$cred_path = $f;
		}
		else {
			croak "no credentials file available!";
		}
	}
	
	# bless early so we can get credentials and token as necessary
	my $self = {
		div     => $division,
		cred    => $cred_path,
		verb    => $verb,
		end     => $endpoint,
		partsz  => $partsize,
		bulksz  => $bulksize,
		napval  => $sleep_val,
	};
	bless $self, $class;
	
		
	# conditional return
	if (defined $division) {
		# go ahead and get token
		unless (defined $token) {
			$token = $self->token;
		}
		return Net::SB::Division->new(
			div     => $division,
			cred    => $cred_path,
			token   => $token,
			name    => $args{name}, # just in case?
			verbose => $verb,
			end     => $self->endpoint,
			partsz  => $partsize,
			bulksz  => $bulksize,
			napval  => $sleep_val,
		);
	}
	else {
		return $self;
	}
}

sub credentials {
	if (exists $_[0]->{divobj}) {
		# for inherited objects
		return $_[0]->{divobj}->credentials;
	}
	else {
		return $_[0]->{cred};
	}
}

sub division {
	my $self = shift;
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->division;
	}
	else {
		return $self->{div};
	}
}

sub endpoint {
	my $self = shift;
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->endpoint;
	}
	else {
		if (@_) {
			my $url = $_[0];
			unless ($url =~ m/^ https: \/ \/ /x) {
				croak "given API endpoint '$url' does not look like a URL!";
			}
			$url =~ s/\/$//; # remove trailing slash
			$self->{end} = $url;
		}
		return $self->{end};
	}
}

sub verbose {
	my $self = shift;
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->verbose;
	}
	else {
		if (@_) {
			$self->{verb} = $_[0];
		}
		return $self->{verb};
	}
}

sub part_size {
	my $self = shift;
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->{partsz};
	}
	return $self->{partsz};
}

sub bulk_size {
	my $self = shift;
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->{bulksz};
	}
	return $self->{bulksz};
}

sub sleep_value {
	my $self = shift;
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->{napval};
	}
	return $self->{napval};
}

sub new_http {
	my $h = HTTP::Tiny->new();
	return $h;
}

sub token {
	my $self = shift;
	
	if (exists $self->{divobj}) {
		# for inherited objects
		return $self->{divobj}->token;
	}
	
	# check token
	unless (defined $self->{token}) {
		# need to collect the token from a credentials file
		my $cred_path = $self->{cred};
		
		# division
		my $division = $self->division || q();
		
		# pull token
		my $token = q();
		my $default_token = q();
		my $default_endpoint = q();
		my $fh = IO::File->new($cred_path) or 
			die "unable to read credentials files!\n";
		my $target = sprintf("[%s]", $division);
		my $line = $fh->getline;
		while ($line) {
			chomp $line;
			if ($line eq $target) {
				# we found the section!
				undef $line;
				my $line2 = $fh->getline;
				while ($line2) {
					chomp $line2;
					if ( $line2 =~ m/^ \[.+\] /x ) {
						# we've gone too far!!!??? start of next section
						$line = $line2;
						undef $line2;
					}
					elsif ($line2 =~ m/^api_endpoint \s* = \s* (https: \/ \/ [\w\/\.\-]+ )$/x) {
						# we found the user's API endpoint
						# go ahead and store it
						$self->endpoint($1);
						$line2 = $fh->getline;
					}
					elsif ($line2 =~ m/^auth_token \s *= \s* (\w+) $/x) {
						# we found the user's token!
						$token = $1;
						$line2 = $fh->getline;
					}
					else {
						$line2 = $fh->getline;
					}
				}
			}
			elsif ($line eq '[default]') {
				# we found the default section
				undef $line;
				my $line2 = $fh->getline;
				while ($line2) {
					chomp $line2;
					if ( $line2 =~ m/^ \[.+\] /x ) {
						# we've gone too far!!!??? start of next section
						$line = $line2;
						undef $line2;
					}
					elsif ($line2 =~ m/^api_endpoint \s* = \s* (https: \/ \/ [\w\/\.\-]+ )$/x) {
						# default fallback endpoint
						$default_endpoint = $1;
						$line2 = $fh->getline;
					}
					elsif ($line2 =~ m/^auth_token \s *= \s* (\w+) $/x) {
						# fallback default token
						$default_token = $1;
						$line2 = $fh->getline;
					}
					else {
						$line2 = $fh->getline;
					}
				}
			}
			else {
				$line = $fh->getline || undef;
			}
		}
		$fh->close;
		if ($token) {
			$self->{token} = $token;
		}
		elsif ($default_token) {
			print STDERR "  using default token for division '$division'\n";
			$self->{token} = $default_token;
			if ($default_endpoint) {
				$self->endpoint($default_endpoint);
			}
		}
		else {
			carp "no token found!";
			return;
		}
	}
	
	return $self->{token};
}

sub execute {
	my ($self, $method, $url, $headers, $data) = @_;
	
	# check method
	unless ($method eq 'GET' or $method eq 'POST' or $method eq 'DELETE') {
		confess "unrecognized method $method! Must be GET|POST|DELETE";
	}
	
	# check URL
	unless (defined $url) {
		confess "a URL is required!";
	}
	
	# check token
	my $token = $self->token;
	unless ($token) {
		my $division = $self->division;
		carp " unable to get token from credentials file for division $division!\n";
		return;
	}
	
	# add standard key values to headers
	if (defined $headers and ref($headers) ne 'HASH') {
		confess "provided header options must be a HASH reference!";
	}
	else {
		$headers ||= {};
	}
	$headers->{'Content-Type'} = 'application/json';
	$headers->{'X-SBG-Auth-Token'} = $token;
	
	# http tiny request options
	my $options = {headers => $headers};
	
	# any post content options
	if (defined $data) {
		unless (ref($data) eq 'HASH') {
			confess "provided POST data must be a HASH reference!";
		}
		$options->{content} = encode_json($data);
	}
	
	# send request
	if ($self->verbose) {
		printf " > Executing $method to %s\n", $url;
		if ($data) {
			printf "   data: %s\n", $options->{content};
		}
	}
	my $response = $http->request($method, $url, $options) or 
		confess "can't send http request!";
	if ($self->verbose) {
		printf " > Received %s %s\n > Contents: %s\n", $response->{status}, 
			$response->{reason}, $response->{content} || q();
	}
	
	# check response
	my $result;
	if ($response->{success}) {
		# success is a 2xx http status code, decode results
		if ($response->{content}) {
			$result = decode_json($response->{content}) ;
		}
		else {
			return 1; # success
		}
	}
	elsif ($method eq 'GET' and $response->{status} eq '404') {
		# we can interpret this as a possible acceptable negative answer
		return;
	}
	elsif ($method eq 'GET' and $response->{status} eq '409') {
		# we can interpret this as a possible acceptable negative answer
		return;
	}
	elsif ($method eq 'DELETE') {
		# not sure what the status code for delete is, but it might be ok
		printf "> DELETE request returned %s: %s\n", $response->{status}, 
			$response->{reason};
		return 1;
	}
	elsif ($response->{status} eq '429') {
		# too many requests! rate limit exceeded
		print STDERR " request limit hit - sleeping for 5 minutes\n";
		sleep 300;
		# repeat the request
		return $self->execute($method, $url, $headers, $data);
	}
	elsif (exists $response->{reason} and $response->{reason} eq 'Internal Exception') {
		confess "http request suffered an internal exception: $response->{content}";
	}
	else {
		carp sprintf("A %s error occured: %s: %s", $response->{status}, 
			$response->{reason}, $response->{content});
		return;
	}
	
	# check for items
	if (exists $result->{items}) {
		my @items = @{ $result->{items} };
		
		# check for more items
		if (exists $result->{links} and scalar @{$result->{links}} > 0) {
			# we likely have additional items, and the next link is conveniently provided
			# get the next link
			my $next;
			foreach my $l (@{$result->{links}}) {
				if (exists $l->{rel} and $l->{rel} eq 'next') {
					$next = $l;
					last;
				}
			}
			# keep going until we get them all
			while ($next) {
				if ($self->verbose) {
					printf " > Executing next %s request to %s\n", $next->{method}, $next->{href};
				}
				my $res = $http->request($next->{method}, $next->{href}, $options);
				if ($res->{reason} eq 'OK') {
					my $result2 = decode_json($res->{content});
					if ($self->verbose) {
						printf "  > Collected %d additional items\n", scalar(@{$result2->{items}});
					}
					push @items, @{ $result2->{items} };
					undef($next);
					foreach my $l (@{$result2->{links}}) {
						if (exists $l->{rel} and $l->{rel} eq 'next') {
							$next = $l;
							last;
						}
					}
				}
				elsif ($res->{status} eq '429') {
					# too many requests! rate limit exceeded
					print STDERR " request limit hit - sleeping for 5 minutes\n";
					sleep 300;
					next;
				}
				else {
					croak sprintf("Failure to get next items with URL %s\n A %s error occurred: %s: %s",
						$next->{href}, $res->{status}, $res->{reason}, $res->{content});
				}
			}
		}
		
		# make sure we don't have duplicates
		# at least the list_divisions method returns a ton of duplicates - a bug?
		# insert sanity check here as a general method, just in case the bug afflicts
		# other things too
# 		my %seenit;
# 		my @keep;
# 		foreach my $i (@items) {
# 			# the href URL should always be unique, so using that as unique key
# 			my $h = $i->{href} || $i->{resource}{href};
# 			next if exists $seenit{$h};
# 			$seenit{$h} = 1;
# 			push @keep, $i;
# 		}
# 		
# 		# done
# 		return wantarray ? @keep : \@keep;
		return wantarray ? @items : \@items;
	}
	
	# appears to be a single result, not a list
	return $result;
}

sub list_divisions {
	my $self = shift;
	return unless ref($self) eq 'Net::SB'; # this should not be accessible by inherited objects
	my $options = {
		'x-sbg-advance-access' => 'advance'
	};
	unless ($self->{div}) {
		$self->{div} = 'default';
	}
	my $token = $self->token; 
		# we don't actually need the token yet, but it will force reading credentials file
		# and update the api endpoint in case it's different from the default value
	my $url = sprintf "%s/divisions", $self->endpoint;
	my $items = $self->execute('GET', $url, $options);
		# there is a bug in their system with this call that messes with their paging 
		# resulting in ten duplicates of everything, so need to identify and discard
		# duplicates
	my @divisions;
	my %seenit;
	foreach (@{$items}) {
		next unless (ref eq 'HASH');
		my $id = $_->{id};
		next if exists $seenit{$id};
		
		# create a new division object for each result
		# copy values to the division object with the exception of token and endpoint
		# since these may be different
		push @divisions, 
			Net::SB::Division->new(
				div     => $id,
				name    => $_->{name},
				href    => $_->{href},
				cred    => $self->credentials,
				verbose => $self->verbose,
				partsz  => $self->part_size,
				bulksz  => $self->bulk_size,
				napval  => $self->sleep_value,
			);
		$seenit{$id} = 1;
	}
	
	return wantarray ? @divisions : \@divisions;
}

sub _encode {
	my ( $self, $value ) = @_;
	$value =~ s/( [%&\=;,\ \#] ) /sprintf("%%%X", ord($1) )/xge;
	return $value;
}

1;

__END__

=head1 NAME

Net::SB - a Perl wrapper around the Seven Bridges API

=head1 SYNOPSIS

    use Net::SB;
    
    # normal usage starts with a division

    my $Division = Net::SB->new(
      division => $division_name
    );  # returns a Net::SB::Division object
    
    my @projects = $Division->list_projects;
       # returns list of Net::SB::Project objects
    
    my @members  = $Division->list_members;
       # returns list of Net::SB::Member objects
    
    
    # otherwise there is very limited functionality
    # with a plain object
    my $sb = Net::SB->new();
    
    # print every http request and response
    $sb->verbose(1);
    
    # default root url endpoint, this may change with division
    my $url = $sb->endpoint;
    
    # manual request when doing something unusual
    my $result = $sb->execute('GET', $url, $headers, $data);
    
    # list all divisions, for enterprise admins only
    my @division_list = $sb->list_divisions;
    
    

=head1 DESCRIPTION

This is a simplified Perl wrapper around the Seven Bridges v2 
L<API|https://docs.sevenbridges.com/reference>.
 
This is not a comprehensive implementation of the full API in its 
entirety. The package primarily focuses on file, project, and member 
management, useful to administrators. It especially allows working 
with files in bulk, something not currently feasible with their 
provided command line tool.

This requires a Developer token to access your Seven Bridges account. 
A Developer token must be generated through the Seven Bridges website.
One or more division tokens may be stored in a credentials file, 
a C<INI>-style text file in your home directory, the default being
F<~/.sevenbridges/credentials>. See Seven Bridges 
L<credentials documentation|https://docs.sevenbridges.com/docs/store-credentials-to-access-seven-bridges-client-applications-and-libraries>.

Many of the base URL paths are hard coded. Changes in the Seven Bridges 
API will likely break one or more methods here.



=head1 METHODS

Net::SB is the main Class. This is inherited by all subclasses, so all of these 
functions should be available everywhere. Start here.

In general, all work begins at the Division level and proceeds to a Project, 
where the majority of work is done. All other objects, including projects, 
members, teams, folders, files, and volumes, are generated via method calls 
starting from here.

=over 4

=item new

Initialize a new object. Usually a division name is provided here and a 
L<Net::SB::Division> object is immediately returned. Otherwise, not much 
can be done with a generic object, other than L<list_divisions>.

Provide parameters as an array of key =E<gt> value pairs. Optional keys 
include the following:

=over 4

=item division

Name of the division to immediately open. 

=item cred cred_path credentials

Provide the local path to your Seven Bridges credentials path, default
 is F<~/.sevenbridges/credentials>. Your access token is obtained 
from this file based on the division name you provided.

=item token

Provide the actual token if known or to overide the value in 
your credential file.

=item endpoint

Provide the API endpoint if it is not in the credential file. 
Default is C<https://api.sbgenomics.com/v2/>.

=item verbose

Provide a true (1) or false (0) value to print every https request
and response. Primarily for debugging purposes.

=item partsize

Specify the upload file part size in bytes (integer). The default 
is equivalent to 32 MB.

=item bulksize

Specify the number of items to provide in bulk API queries, default 100.

=item sleepvalue

Specify the number of seconds to sleep before checking a result for bulk 
or asynchronous API calls. The default is 60 seconds.

=back

=item credentials

Return the credentials file path. 

=item division

Returns the division name. Required to do any work.

=item token

Returns the token for the given division, obtained automatically from 
the credentials file if not explicitly given. 

=item endpoint

Returns and sets the API endpoint. The default value is 
C<https://api.sbgenomics.com/v2/>, but this value will be 
overridden by the C<api_endpoint> tag in the credentials file.

=item verbose($verbosity)

Sets and returns verbosity boolean value: 1 is true, 0 is false.

=item part_size

Returns the upload file part size in bytes.

=item bulk_size

Returns the number of items to include in bulk API calls.

=item sleep_value

=item new_http

Convenience method to return a brand new L<HTTP::Tiny> object.

=item token

Returns the token for the current division. If it has not been 
fetched yet, it will open and parse the credentials file and 
extract the token.

=item execute($method, $url, \%header_options, \%data)

Main function for executing an API C<https> request. Most users shouldn't 
need to run this, unless a method doesn't exist. Pass at a minimum the 
HTTP method type (C<GET>, C<POST>, C<DELETE>) and the complete URL path.

Two additional positional items may be provided as necessary. For simple
queries, neither are required. First, a hash reference of additional header
items. The division token is automatically supplied here and isn't necessary.
Second, a hash reference of additional data content to be provided for 
C<POST> submissions. 

All results are returned from Seven Bridges as JSON and is parsed into Perl
objects. When expecting lists of results, e.g. member or project lists, these
are parsed and placed into an array and returned as an array or array reference.
Non-list results are parsed and returned as a hash. Be B<very> careful on what
you expect. 

=item list_divisions

Primarily for Enterprise super admins. Lists all divisions for which you are a
member. Returns a list or array reference of L<Net::SB::Division> objects
corresponding to each division.

=back


=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatic Analysis Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  


