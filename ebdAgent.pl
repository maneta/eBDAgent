#!/usr/bin/perl -w
#
## ebdAgent.pl
## by Daniel Cesario
## (c) AppBrige

use strict;
use warnings;
use YAML qw(LoadFile);
use Data::Dumper;


sub init {
##Read The Domain List for Monitorize 

	
	my @domains;
	eval {
		@domains = LoadFile("domains.yml");
	};
	warn $@ if $@;

	print Dumper(@domains);
}
################BEGIN##################

init();

