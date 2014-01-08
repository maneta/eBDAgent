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

my $CONFIG;

my $CONFIG_FILE = "agent_conf.yml";

sub load_config {
##Read The Configuration from a YAML file. 

	$CONFIG = LoadFile("$CONFIG_FILE") or die "Missing $CONFIG_FILE File";
	#ToDo: Make a Hash to check the Configuration Parameters Like
=pod
	my $error = 0;
        for my $arg (sort keys %CONFIG_ARGS) {
                if (!$CONFIG_ARGS{$arg} && ! $CONFIG->{$arg}) {
                                warn "Missing configuration for $arg in $FILE_CONFIG\n";
                                $error++;
                }
                ${$CONFIG_ARGS{$arg}} = $CONFIG->{$arg}        if $CONFIG->{$arg};
        warn "ERROR: Paràmetre $arg desconegut a $FILE_CONFIG\n"
            if !exists $CONFIG_ARGS{$arg};
        }
        exit -1 if $error;
=cut
}

sub check_global {
	my $domains = $CONFIG->{domains};
	my $ua = LWP::UserAgent->new;
 	$ua->timeout(10);
	$ua->agent('eBDAgent/1.0');
 	foreach (@$domains) {
		eval{
			my $response = $ua->get("http://$_/");
 
			if ($response->is_success) {}
 			else {
     				die $response->status_line;
 			}
		}; 
		if ($@) {
			warn $@;
			#ToDo: Create a Hash with the Report Info
		}
	}
};
sub check_local {
	my $domains = $CONFIG->{domains};
        foreach (@$domains) {
		LWP::UserAgent::DNS::Hosts->register_host("$_" => '127.0.0.1',);
		LWP::UserAgent::DNS::Hosts->enable_override;
		my $ua = LWP::UserAgent->new;
		$ua->timeout(10);
		$ua->agent('eBDAgent/1.0');
                eval{
                        my $response = $ua->get("http://$_:8080");

                        if ($response->is_success) {
                                print $response->decoded_content;
				#next;
                        }
                        else {
                                die $response->status_line;
                        }
                };
                if ($@) {
                        warn $@;
			#ToDo: Create a Hash with the Report Info
                }
        }
}; 

################BEGIN##################

load_config();
check_global;
check_local;
