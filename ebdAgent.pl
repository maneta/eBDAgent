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
use Unix::Passwd::File qw(get_user);
use Filesys::Df;
use Email::Sender::Simple qw(sendmail);
use Email::MIME;

my $CONFIG;
my $CONFIG_FILE = "agent_conf.yml";
my $APACHE_PORT;
my $EBD_SERVER_PORT;
my $EBD_TSERVER_PORT;
my $MYSQL_SERVER_PORT;
my $HOME_EBD;
my $USER_EBD;
my $EBD_ENV;
my $RETRY;
my $DISK_PERCENT_WARNING;
my $SERVER_NAME;
my $AGENT_EMAIL;
my $ADMIN_EMAIL;
my $REPORT_SEND = 0;

#The Report Hash
my %REPORT = ( 	http_global => "OK\n",
		http_local => "OK\n",
		apache_server => "OK\n",
		ebd_server => "OK\n",
		ebd_tserver => "OK\n",
		mysql_server => "OK\n",
		disk_usage => "OK\n"
	     	);

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
	$USER_EBD = $CONFIG->{eBD}->{user};	
	my $user = get_user(user=>"$USER_EBD");
        $HOME_EBD = $user->[2]->{home};


	#get the number of Retries to get service UP (Apache,ebd_server,tserver)
	$RETRY = $CONFIG->{services}->{retry};
	
	#Get the disk usage percent warning 
	$DISK_PERCENT_WARNING = $CONFIG->{warnings}->{disk};
	
	#Get the server name
	$SERVER_NAME = $CONFIG->{server_name};
	
	#Get the agent & admin(s) email(s)
	$AGENT_EMAIL = $CONFIG->{agent_email};
	$ADMIN_EMAIL = $CONFIG->{admin_email};
	
	my $env_set =  "source $HOME_EBD/bin/ebd_env.sh ";
	$EBD_ENV = Shell::GetEnv->new( 'sh', $env_set );
	
}

sub check_global {
	my $global_response;
	my $domains = $CONFIG->{domains};
	my $retry = 0;
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
          		$retry++;
                	if ($retry >= $RETRY){
                        	my $report = "The domain $domains is not accesible from the Internet, please check the Services. Error Code:   $@\n";
				$REPORT{http_global} = $@;
				$REPORT_SEND = 1;
				send_report();
				
				#Cleaning the report send variable and restoring the Hash 
				#for its default value
				$REPORT{http_global} = 'OK';
				$REPORT_SEND = 0;
                	}else{
				sleep 5;
                        	check_global();
        		}
		}else{
			check_local($domain,$global_response,0);
		}
	}
};

sub check_local {
	my ($domain,$global_response,$retry) = @_;
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
			die  "Local HTML Global Title for the web $domain do not match with the Local Title. Please Review your proxy or Contact with your System Administrator.\n"
			unless ($local_response eq $global_response);
		}else{
                	die $response->status_line;
                }
	};
        if ($@) {
		$retry++;
		if ($retry >= $RETRY){
			$REPORT{http_local} = $@;
			$REPORT_SEND = 1;
			send_report();
			
			#Cleaning the report send variable and restoring the Hash 
			#for its default value
			$REPORT{http_local} = 'OK';
			$REPORT_SEND = 0;
			
                }else{
			sleep 5;
			check_local($domain,$global_response,$retry);	
		}
	}
};
 
sub check_services {
	my %services = ( apache_server => $APACHE_PORT,
			 ebd_server => $EBD_SERVER_PORT,
			 ebd_tserver => $EBD_TSERVER_PORT,
			 mysql_server => $MYSQL_SERVER_PORT
	      		 );

	while (my ($service, $port) = each %services){
    		_do_check_port($service, $port, 0);	
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
		
		# Asumption that the MySQL service should and special Atention
		if ($retry >= $RETRY || $service eq 'mysql_server'){
			my $report = "The $service, port $port on the server $SERVER_NAME is Down\n";
			$REPORT{$service} = $report;
			$REPORT_SEND = 1;
		}else{
			$retry++;
			my $command = "$HOME_EBD/bin/$service start";
        		
			unless($service eq 'apache_server' && $port == 80) {

				$command = "su $USER_EBD -c \"$HOME_EBD/bin/$service start\"";
			}

			eval{
                		open my $run, '-|', $command or die $!;
				while (<$run>) {
					sleep 5;
				        last;
				}
				 
        			close $run;
        		};
				_do_check_port($service,$port,$retry)
		}
		
        }
};

sub retrieve_ports {

	my $c1 = Apache::ConfigParser->new;
	$c1->parse_file("$HOME_EBD/conf/httpd.conf")
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
	my $data = $xml->XMLin("$HOME_EBD/app/conf/ebd_config.xml") or die "Cannot Parse the Config File";

	#Retrieve the ebd_server from ebd_config.xml file
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

sub check_disk {
	my $ref = df("$HOME_EBD",1);  
  	if(defined($ref)) {
     		if ($ref->{per} >= $DISK_PERCENT_WARNING){
			my $report = "The Disk Usage for the Server $SERVER_NAME is: ".$ref->{per}."% Please Check the Disk\n";
                        $REPORT{disk_usage} = $report;
			$REPORT_SEND = 1;
		}	
	}else{
		my $report = "Cannot reach the Disk on the Server $SERVER_NAME\n";
		$REPORT{disk_usage} = $report;
		$REPORT_SEND = 1;
	}
};

sub send_report {
	
	if($REPORT_SEND == 1){
	
	  foreach(@$ADMIN_EMAIL){
		my $message = Email::MIME->create(
                            	header_str => [
                                From => "$AGENT_EMAIL",
                                To => "$_",
                                Subject => "[eBD Agent] - Server: $SERVER_NAME Report",
                            	],
                            	attributes => {
                                encoding => 'quoted-printable',
                                charset => 'ISO-8859-1',
                            	},
                            	body_str => "This is the  Server $SERVER_NAME Report: \n \n".
					    "The GLOBAL WebService Status is: ".$REPORT{http_global}.
					    "The LOCAL WebService Status is: ".$REPORT{http_local}.
					    "The Apache service Status is: ".$REPORT{apache_server}.
					    "The EBD SERVER service Status is: ".$REPORT{ebd_server}.
					    "The EBD TSERVER service Status is: ".$REPORT{ebd_tserver}.
					    "The MySQL service Status is: ".$REPORT{mysql_server}.
					    "The Disk Usage Status is: ".$REPORT{disk_usage}.
					    "\n Please Review your Server"
					    ,
                        	);
		sendmail($message);
	  }
	}
}; 

#########################################################

load_config();
retrieve_ports();
check_services();
check_disk();
check_global();
send_report();
