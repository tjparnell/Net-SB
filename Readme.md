# Net::SB

This is a general purpose Perl API for interacting with the bioinformatics cloud platform
[Seven Bridges](https://www.sevenbridges.com), as well as
[Cancer Genomics Cloud](https://www.cancergenomicscloud.org). 

It is a wrapper around their published 
[API](https://docs.sevenbridges.com/page/api). This by no means has complete coverage, 
but it has been sufficient for my purposes. It is primarily focused on the following areas.

- Division management, including listing divisions.

- Project management, including listing, creating, and modifying projects.

- User management, including listing users, adding users to projects, and modifying 
permisions of users within projects.

- Team management, including creating teams and adding users.

- File management, including listing files recursively through nested folders, 
filtering files, generating download URLs, and uploading files.

- Volume management, including adding AWS volumes and bulk exporting files to the 
volume.

There is currently no management of tasks or billing.



## Requirements

Since this is a cloud platform, you will of course need a login to the platform. 
In addition, you will also need to generate your 
[Seven Bridges credentials file](https://docs.sevenbridges.com/docs/store-credentials-to-access-seven-bridges-client-applications-and-libraries) 
with a developer tokens for your default division.

Consequently, because of this requirement, the included tests are extremely limited and
do not perform any network activity.

## Implementation

See the [HCI-Bio-Repository](https://github.com/HuntsmanCancerInstitute/hci-bio-repository)
for a practical implementation, specifically the application script
[sbg_project_manager](https://github.com/HuntsmanCancerInstitute/hci-bio-repository/blob/master/bin/sbg_project_manager.pl).


# Installation

This may be installed with the usual incantation.

    perl Makefile.PL
    make
    make install

Or it may be installed with an appropriate Perl package manager, such as 
[CPANminus](https://metacpan.org/pod/App::cpanminus) or CPAN.


# License

This package is free software; you can redistribute it and/or modify
it under the terms of the Artistic License 2.0.  

	 Timothy J. Parnell, PhD
	 Bioinformatic Analysis Shared Resource
	 Huntsman Cancer Institute
	 University of Utah
	 Salt Lake City, UT, 84112

