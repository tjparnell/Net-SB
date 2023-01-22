package Net::SB::Volume;

use strict;
use Carp;
use File::Spec;
use File::Spec::Unix; # we pretend everything is unix based
use base 'Net::SB';

our $VERSION = Net::SB->VERSION;

# internal factors for checking
my $adv_headers = {
	'x-sbg-advance-access' => 'advance'
};

sub new {
	my $class = shift;
	my $division = shift;

	# check if we have SBG result hash
	if (ref $_[0] eq 'HASH' and exists $_[0]->{href}) {
		my $self = shift @_;
		$self->{divobj} = $division;
		return bless $self, $class;
	}

	# options for making new volume
	my %options = @_;
	$options{type}   ||= 's3';
	$options{bucket} ||= q();
	$options{divobj} = $division;

	# return 
	if ($options{type} eq 's3') {
		return _new_s3($class, \%options);
	}
	elsif ($options{type} eq 'gcs') {
		return _new_gcs($class, \%options);
	}
	else {
		carp "unrecognized volume type!";
		return;
	}
}

sub _new_s3 {
	my ($class, $options) = @_;
	my $key_id =
		$options->{access_key_id} ||
		$options->{credentials}{access_key_id} ||
		undef;
	my $secret_key =
		$options->{secret_access_key} ||
		$options->{credentials}{secret_access_key} ||
		undef;
	my $mode = $options->{access} || $options->{mode} || 'RO';
	my $division = $options->{divobj};

	# check
	unless ($key_id and $secret_key and $options->{bucket} and $options->{name}) {
		carp "missing credential and/or bucket information!";
		return;
	}
	unless ($mode eq 'RO' or $mode eq 'RW') {
		carp "unknown access mode '$mode'!";
		return;
	}

	# request
	my $data = {
		name        => $options->{name},
		service     => {
			type        => 's3',
			bucket      => $options->{bucket},
			prefix      => $options->{prefix} ||= q(),
			credentials => {
				access_key_id       => $key_id,
				secret_access_key   => $secret_key
			},
		},
		access_mode => $mode,
	};
	my $url = sprintf "%s/storage/volumes", $division->endpoint;
	my $result = $division->execute('POST', $url, $adv_headers, $data);
	if ($result) {
		# example structure
		# {
		#   "href": "https://api.sbgenomics.com/v2/storage/volumes/rfranklin/my_volume",
		#   "id": "rfranklin/my_volume",
		#   "name": "my_volume",
		#   "access_mode": "RO",
		#   "service": {
		# 	"type": "S3",
		# 	"bucket": "sb-demo-markot-ro",
		# 	"prefix": "input-files",
		# 	"endpoint": "s3.amazonaws.com",
		# 	"credentials": {
		# 	  "access_key_id": "AKIAI32ALEL3XDGMNQ2Q"
		# 	},
		# 	"properties": {
		# 	  "sse_algorithm": "aws:kms",
		# 	  "sse_aws_kms_key_id": "test_kms_key_id"
		# 	}
		#   },
		#   "created_on": "2017-07-21T08:23:39Z",
		#   "modified_on": "2017-07-21T08:23:39Z",
		#   "active": true
		# }
		my $self = $result;
		$self->{divobj} = $division;
		return bless $self, $class;
	}
	else {
		carp sprintf "problems attaching volume '%s'!", $options->{bucket};
		return;
	}
}

sub _new_gcs {
	croak "not implemented!";
}

sub href {
	return shift->{href};
}

sub id {
	return shift->{id};
}

sub name {
	return shift->{name};
}

sub prefix {
}

sub get_details {
	my $self = shift;
	my $result = $self->execute('GET', $self->href, $adv_headers);
	$self->{active} = $result->{active};
	$self->{description} = $result->{description};
	$self->{access_mode} = $result->{access_mode};
	$self->{service} = $result->{service};
	$self->{created_on} = $result->{created_on};
	$self->{updated_on} = $result->{updated_on};
}

sub mode {
	my $self = shift;
	unless (exists $self->{access_mode}) {
		$self->get_details;
	}
	return $self->{access_mode};
}

sub service {
	# hash reference on the service stuff, like bucket, endpoint, etc
	my $self = shift;
	unless (exists $self->{service}) {
		$self->get_details;
	}
	return $self->{service};
}

sub active {
	my $self = shift;
	unless (exists $self->{active}) {
		$self->get_details;
	}
	return $self->{active};
}

sub activate {
	my $self = shift;
	my $data = {
		active => 'true'
	};
	my $result = $self->execute('PATCH', $self->href, $adv_headers, $data);
	if ($result and $result->{active} eq 'true') {
		return 1;
	}
	else {
		return 0;
	}
}

sub deactivate {
	my $self = shift;
	my $data = {
		active => 'false'
	};
	my $result = $self->execute('PATCH', $self->href, $adv_headers, $data);
	if ($result and $result->{active} eq 'false') {
		return 1;
	}
	else {
		return 0;
	}
}

sub delete {
	my $self = shift;
	unless ($self->active eq 'true') {
		$self->deactivate;
	}
	my $result = $self->execute('DELETE', $self->href, $adv_headers);
	if ($result) {
		# empty self? what else to do here?
		$self = {
			href  => q(),
			id    => q(),
			name  => q()
		};
		return 1;
	}
	return 0;
}

sub list_files {
	croak "not implemented!";

}


sub import_files {
	croak "not implemented!";
}

sub export_files {
	my $self = shift;
	my %options = @_;
	unless ($self->mode eq 'RW') {
		carp 'volume is not in Read/Write mode!';
		return;
	}
	my $files = $options{files} || undef;
	my $copy  = exists $options{copy} ? $options{copy} : 0;
	my $overwrite = exists $options{overwrite} ? $options{overwrite} : 0;
	my $prefix = $options{prefix} || q();
	unless (ref $files eq 'ARRAY') {
		carp 'pass an array reference of File objects!';
		return;
	}

	# generate URLs
	my $url1 = sprintf "%s/bulk/storage/exports/create", $self->endpoint;
	if ($copy) {
		$url1 .= '?copy_only=true';
	}
	my $url2 = sprintf "%s/bulk/storage/exports/get", $self->endpoint;

	# loop through files
	my $sleep_time = $self->sleep_value;
	my $bulk_size  = $self->bulk_size;
	my $batch_count = 1;
	my %file_results;
	while (@{$files}) {
		# generate list of files to go
		# we will use the bulk export call that can handle up to 100 at a time
		my @items;
		while (@{$files}) {
			my $file = shift @{$files};
			unless (ref $file eq 'Net::SB::File') {
				next;
			}
			# prepare data item for request
			my $destination = $prefix ? File::Spec::Unix->catfile(
						$options{prefix}, $file->pathname) : $file->pathname;
			my $id = $file->id;
			push @items, {
				source  => {
					file     => $id
				},
				destination => {
					volume   => $self->id,
					location => $destination
				},
				overwrite => $overwrite ? 'true' : 'false'
			};
			# prepare result hash
			$file_results{$id} = {
				source      => $file->pathname,
				destination => File::Spec::Unix->catfile($self->id, $destination),
				status      => q(),
				transfer_id => q()
			};
			last if scalar(@items) == $bulk_size;
		}

		# submit export request
		my $data = {
			items => \@items
		};
		my $results = $self->execute('POST', $url1, $adv_headers, $data);
		# initialize counts
		my $working_count = scalar @items;
		my $finish_count = 0;
		my $error_count  = 0;
		my @check;

		# go through initialization results
		for (my $i = 0; $i < scalar @{$results}; $i++) {
			my $r = $results->[$i];
			if (exists $r->{error}) {
				# request did not succeed - likely because it was a link to an external 
				# resource that can't exported
				my $id = $items[$i]->{source}{file}; # assuming order is the same
				# record errors, nothing to check later
				$file_results{$id}{status} = 'FAILED';
				$working_count--;
				$error_count++;
				$file_results{$id}{error} = $r->{error}{code};
			}
			else {
				my $id = $r->{resource}{source}{file};
				$file_results{$id}{status} = $r->{resource}{state};
				$file_results{$id}{transfer_id} = $r->{resource}{id};
				push @check, $r->{resource}{id};
			}
		}

		# collect and check results
		sleep $sleep_time if $working_count;
		while ($working_count) {
			# first reset pending and running counts
			# print STDERR " > checking on $working_count items\n";
			my $pending_count = 0;
			my $running_count = 0;

			# collect the status
			$data = {
				export_ids => \@check
			};
			$results = $self->execute('POST', $url2, $adv_headers, $data);

			# reset check list and loop through results
			@check = (); # reset for next round
			foreach my $r (@{$results}) {
				if (exists $r->{error}) {
					# request failed for some reason
					# no easy way to track this back to a transfer ID
					$working_count--;
					$error_count++;
				}
				else {
					my $status = $r->{resource}{state};
					my $id = $r->{resource}{source}{file} || q();
					$file_results{$id}->{status} = $status;
					if ($status eq 'PENDING') {
						push @check, $r->{resource}{id};
						$pending_count++;
					}
					elsif ($status eq 'RUNNING') {
						push @check, $r->{resource}{id};
						$running_count++;
					}
					elsif ($status eq 'COMPLETED') {
						$working_count--;
						$finish_count++;
					}
					elsif ($status eq 'FAILED') {
						# not sure if this will ever pop up here, but just in case....
						$working_count--;
						$error_count++;
						if ($id) {
							$file_results{$id}{error} = $r->{error}{code};
						}
					}
					else {
						carp "unrecognized status '$status' received!\n";
					}
				}
			}

			# print status
			printf STDERR " > batch %4s: %3s pending, %3s running, %3s completed, %3s failed\n",
				$batch_count, $pending_count, $running_count, $finish_count, $error_count;

			# wait before checking again
			# print STDERR " > sleeping $sleep_time\n";
			sleep $sleep_time if $working_count;
		}
		# finished with this batch
		$batch_count++;
	}

	return \%file_results;
}

1;

=head1 Net::SB::Volume

Class object representing an attached volume on the Seven Bridges platform. 
Currently only supporting attached AWS buckets. This should be called from a 
Net::SB:Division object.

See Net::SB documentation for details.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Bioinformatics Shared Resource
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  



