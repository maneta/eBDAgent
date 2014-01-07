#!/usr/bin/perl -w
#
## ebdAgent.pl
## by Daniel Cesario
## (c) AppBrige

use strict;
use warnings;
use YAML qw(LoadFile);
use Data::Dumper;
use LWP::UserAgent;
use LWP::UserAgent::DNS::Hosts;

my @DOMAINS;

sub init {
##Read The Domain List from a file. 

	my $filename = 'domains.dat';
	open(my $fh, '<', $filename)
	  or die "Could not open file '$filename' $!";
	@DOMAINS = <$fh>;
	close $fh;
}

sub check_global {
	my $ua = LWP::UserAgent->new;
 	$ua->timeout(10);
 	foreach (@DOMAINS) {
		chomp($_);
 		eval{
			my $response = $ua->get("http://$_/");
 
			if ($response->is_success) {
			#	print $response->decoded_content;  # or whatever
 			}
 			else {
     				die $response->status_line;
 			}
		}; 
		if ($@) {
			warn $@;
		}
		
	}
};

################BEGIN##################

init();
check_global;
#check_local;
