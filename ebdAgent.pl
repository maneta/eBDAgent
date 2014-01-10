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
use Apache::ConfigParser;
use XML::Simple;
use IO::Socket::INET;
use Shell::GetEnv;

my $CONFIG;
my $CONFIG_FILE = "agent_conf.yml";
my $APACHE_PORT;
my $EBD_SERVER_PORT;
my $EBD_TSERVER_PORT;
my $MYSQL_SERVER_PORT;
my $HOME_EBD;
my $EBD_ENV;
my $RETRY;

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
	#get the eBD home
	$HOME_EBD = $CONFIG->{eBD}->{home};
	
	#get the number of Retries to get service UP (Apache,ebd_server,tserver)
	$RETRY = $CONFIG->{services}->{retry};
	
	my $env_set =  "source $HOME_EBD/bin/ebd_env.sh ";
	$EBD_ENV = Shell::GetEnv->new( 'sh', $env_set );
	
	my $command = "$HOME_EBD/bin/ebd_server start";
	eval{
		open my $run, '-|', $command or die $!;
       		while (<$run>) {
        		 print;
        	}
        close $run;
	};

	if ($@) {
                warn $@;
                #ToDo: Create a Hash with the Report Info
        }
}

sub check_global {
	my $global_response;
	my $domains = $CONFIG->{domains};
	my $ua = LWP::UserAgent->new;
 	$ua->timeout(10);
	$ua->agent('eBDAgent/1.0');
 	foreach (@$domains) {
		my $domain = $_;
		eval{
			my $response = $ua->get("http://$domain/");
 
			if ($response->is_success) {
				$global_response = $response->title();
			}
 			else {
     				die $response->status_line;
 			}
		}; 
		if ($@) {
			warn $@;
			#ToDo: Create a Hash with the Report Info
		}else{
			check_local($domain,$global_response);
		}
	}
};
sub check_local {
	my ($domain,$global_response) = @_;
	my $local_response;
	LWP::UserAgent::DNS::Hosts->register_host("$_" => '127.0.0.1',);
	LWP::UserAgent::DNS::Hosts->enable_override;
	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);
	$ua->agent('eBDAgent/1.0');
        
	eval{
        	my $response = $ua->get("http://$_:$APACHE_PORT");
		if ($response->is_success) {
			$local_response = $response->title();
			die  "Local HTML Title: $local_response does not Match with Global HTML Title: $global_response"
			unless ($local_response eq $global_response);
		}else{
                	die $response->status_line;
                }
	};
        if ($@) {
		warn $@;
		#ToDo: Create a Hash with the Report Info
	}
}; 
sub check_services {
	my %services = ( apache => $APACHE_PORT,
			 ebd_server => $EBD_SERVER_PORT,
			 ebd_tserver => $EBD_TSERVER_PORT,
			 mysql_server => $MYSQL_SERVER_PORT
	      		 );

	while (my ($service, $port) = each %services){
    		_do_check_port($service, $port);	
	}
	
		
};

sub _do_check_port{

	my ($service,$port,$retry) = @_;	
 
	my $socket = IO::Socket::INET->new( PeerAddr => '127.0.0.1',
                                            PeerPort => $port,
                                            Proto    => 'tcp'
                                            );
        if ($socket) {
        	warn "The service $service on port $port is UP!\n";
        }else{
         	warn "The service $service on port $port is DOWN!\n";
		
		$retry++;
		
        }

};

sub retrieve_ports {
	#ToDo:
	#  -Retrieve the Apache Port from Listen directive on httpd.conf
	#  Needs to get the EBD_HOME env variable in order to make it
	#  Dynamic.

	my $c1 = Apache::ConfigParser->new;
	$c1->parse_file('/usr/eBDAS/conf/httpd.conf')
	or die "Cannot Parse the Config File";
	
	#Somehow it works! finds the Listen Directive Value on the Apache
	#httpd.conf File
	my %parsed_config = map {
        my ($directive) = ( $c1->find_down_directive_names($_) );
        		defined($directive) ? ( $_, $directive->value ) : ()
   	 		} qw(Listen);
	$APACHE_PORT = $parsed_config{Listen};
	
	# create object
	my $xml = new XML::Simple;
	# read XML file
	my $data = $xml->XMLin("/usr/eBDAS/app/conf/ebd_config.xml") or die "Cannot Parse the Config File";

	#print Dumper($data);
	#  -Retrieve the ebd_server from ebd_config.xml file
	$EBD_SERVER_PORT = $data->{eBDServer}->{Port};

	#Retrieve the ebd_tserver port from ebd_config.xml
	$EBD_TSERVER_PORT = $data->{TServer}->{Server}->{Port};

	#Retrieve the Catalog mysql server port from ebd_config.xml
	my $mysql_array_ref = $data->{TServer}->{DBDriver};

	foreach(@$mysql_array_ref){
		next if ($_->{Type}) ne ('MySQL');
		$MYSQL_SERVER_PORT = $_->{DefaultPort};
		last; 
	}
};
################BEGIN##################

load_config();
retrieve_ports();
check_services();
check_global();
