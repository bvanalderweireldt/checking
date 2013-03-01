#!/usr/bin/env perl
# Checking Perl
# Vanalderweireldt Benoit
# 4/12/2012

BEGIN{
	use File::Basename;
	eval 'use lib "'.dirname(__FILE__).'"';
	eval 'chdir "'.dirname(__FILE__).'"';
}

use strict;
use warnings;
use Db;
use Site;
use Email;
use Utils;
use MIME::Lite;
use File::Slurp;
use Log::Log4perl;
use threads;
use Try::Tiny;
use utf8;
#
#
# Global Configuration
#
#
my $conf_path = "conf/";
my $db_target = "checking_dweb";
my $gzip = 1;
my $siteid = 0;
my $userid = undef;
my $log = $conf_path."log4p-prod.conf";


#
#
# Filling global conf from args
#
#
foreach my $arg ( @ARGV ){
	if( $arg =~ /db=\w+/i ){
		$db_target = Utils::extractArgFromString({ arg => $arg });
	}
	elsif( $arg =~ /gzip=(0|1)/i ){
		$gzip = Utils::extractArgFromString({ arg => $arg });
	}
	elsif( $arg =~ /siteid=\d+/i){
		$siteid = Utils::extractArgFromString({ arg => $arg })
	}
	elsif( $arg =~ /userid=\d+/i){
		$userid = Utils::extractArgFromString({ arg => $arg })
	}
	elsif( $arg =~ /debug/i ){
		$log = $conf_path."log4p-debug.conf";
	}
	elsif( $arg =~ /-h/i ){
		Utils::displayHelp();
		exit 0;
	}
	else{
		die("Error wrong argument passed, type -h to see help !");
	}
}

#
#
# Init Logger
#
#
Log::Log4perl->init($log);
my $LOGGER = Log::Log4perl->get_logger("");

#
#
#Connecting to db
#
#
my $db = Db->new({ db_target => $db_target });

#load general keywords to check in every website, trigger an alert in one of these keywords is found
$LOGGER->debug("Loading global keywords !");
my @keywords = $db->loadkeywords();

#
#
#Do we just deal with one site ?
#
#
if( $siteid != 0 ){
	my @row = $db->loadSiteFromId( { siteid => \$siteid } );
	die("Empty Site ?") if !@row; 
	my $site_to_check = Site->newFromDbArray( { site => \@row } );
	$site_to_check->setStatus( 20 );

	$site_to_check->checkSite( { 	keywords => \@keywords, 
									email => undef  } );

	$LOGGER->debug("Inserting operation for website : ".$site_to_check->getAddress());
	$site_to_check->save_operation( { db => \$db, gzip => $gzip } );
	$db->updateSiteSatus( { status =>  $site_to_check->getStatus(), id => $site_to_check->getId() } );
	exit 0;
}

#
#
#Do we just deal with one user ?
#
#
my $emails_db;
if( defined $userid ){
	$LOGGER->info("Loading one Email id : $userid");
	$emails_db = $db->loadEmailByUserId({ userid => $userid });
}
else{
	$LOGGER->info("Loading all Emails !");
	$emails_db = $db->loadEmails();
}

#
#
#If their is no emails to check we stop here
#
#
$LOGGER->info("No email to check !") and exit 0 unless scalar($emails_db) > 0;

#
#
#Emails account array
#
#
my @emails;

#
#
#Main loop get site from email and check it
#
#
$LOGGER->debug("Scanning to find what emails account have to be check !");
my $frequency = Utils::getFrequency();
my $timeSlot = Utils::getTimeSlot();
while( my @email = $emails_db->fetchrow_array) {
		
	if (! defined $email[0] or $email[0] eq ""){
		$LOGGER->error("Empty email, go to the next one !");
		next;
	}
	$LOGGER->debug("Analizing : ".$email[0]);
	
	#if the site is activate but have no frequency we set it to 4 hours
	$email[4] = ( ( 60 / $frequency ) * 4 ) unless ( defined $email[4] && $email[4] ne 0 );
	#if the website don't have to be check now we go to the next one
	my $r = $timeSlot % $email[4];

	$LOGGER->info("Ignore : ".$email[0]) and next unless ( $r == 0 || defined $userid );
	
	$LOGGER->info("#### Find one email account to check ".$email[0].", now will load websites associates.");
	#we a new email and save it into the global array of email
	my $emailToNotify = Email->new( { 
		id => $email[5],
		email => $email[0], 
		nom => $email[1], 
		prenom => $email[2], 
		cc => $email[3], 
		frequency => $email[4],
		force_email => $email[6],
		lang => $email[7] });
	push( @emails, $emailToNotify );
	undef @email;
	my $monitor = ( ! defined $userid )?"1":"0,1";
		
	my $websites_db = $db->loadWebsitesEmailAccount( { monitor => $monitor, user_id => $emailToNotify->getId() } );
	
#
#
# Multi Thread part, we will launch one thread for every site, with a maximum of $nb_process threads	
#
#	
	my $nb_process = 5; #Number of simultaneous process that can run
	my $nb_compute = $websites_db->rows; # Number of sites(process) we will need to run
	my @sites;
	my @running = ();
	my @joinable = ();
	my $i = 0;
	my $total = $websites_db->rows;
	
	while ( my @website = $websites_db->fetchrow_array() ){
		my $site = Site->newFromDbArray( { site => \@website } );
		undef @website;#We unrefence the ressource from array;
		
		#While we cannot launch a new thread we wait
		while( 1 ){
			@running = threads->list(threads::running);
			if( scalar @running < $nb_process ){
				$LOGGER->debug("Thread ".$i." / ".$total." , new thread -> link to ".$emailToNotify->getEmail()." : ".$site->getAddress());
				my $thread = threads->new({'context' => 'list'}, sub { \$site->checkSite( { keywords => \@keywords } ) });
				$i++;
				last; #We just create a new thread, so we leave the while, to get a new website bd array
			}
			else{
				$LOGGER->debug("All thread are busy need to wait.");
				sleep(1);
			}
			
			#
			#
			# We try to close thread that can be close, to avoid high memory peak
			#
			#
			@joinable = threads->list();
			foreach my $thread ( @joinable ){
				if( $thread->is_joinable() ){
					my $site_to_save = $thread->join();
					$LOGGER->debug("Found one thread to finish : ".$thread->tid());
					if( defined $site_to_save ){
						try{
							${$site_to_save}->Site::save_operation( { db => \$db, gzip => \$gzip } );
							$db->updateSiteSatus( { status =>  ${$site_to_save}->getStatus(), id => ${$site_to_save}->getId() } );
							$emailToNotify->addSiteRef( $site_to_save );
							try{
								$thread->kill('KILL')->detach; 
							}
							catch{
								#We join the thread already, but just to be sure
							}
						}
						catch{
							$LOGGER->debug("Cannot save a site operation !!!".$_);
						};
					}
					else{
						$LOGGER->error("The ref returned by the thread is empty !!!");
					}
					undef $site_to_save;
				}
			}
		}
		
	}
	#
	#
	# We close the unfinished thread
	#
	#
	foreach my $thread ( threads->list() ){
		if( defined $thread ){
			try{
				my $site_to_save = $thread->join();
				try{
					${$site_to_save}->Site::save_operation( { db => \$db, gzip => \$gzip } );
					$db->updateSiteSatus( { status =>  ${$site_to_save}->getStatus(), id => ${$site_to_save}->getId() } );
					$emailToNotify->addSiteRef( $site_to_save );
					try{
						$thread->kill('KILL')->detach;
					}
					catch{
						#We join the thread already, but just to be sure
					}
				}
				catch{
					$LOGGER->error("Cannot save a site operation !!!".$_);
				}
			}
			catch{
				$LOGGER->debug("This thread is closed already !!!");
			}
		}
	}
}
#
#
#Send emails
#
#
$LOGGER->debug("Starting the email loop, must send : ".scalar(@emails)." email(s)");
foreach my $email_account ( @emails ){
	my $mail_template = read_file( "mail_template/basic-".$email_account->getLang().".html" );
	$LOGGER->debug("Preparing mail content for : ".$email_account->getEmail());

	if( $email_account->getCountSites() == 0 ){
		$LOGGER->debug("This account have no websites, go to the next !");
		next;
	}

	if( $email_account->hasOneError() == 0 && $email_account->getForceEmail() == 0 ){
		$LOGGER->debug("No error detected and mail is not set to force, skip to the next one !");
		next;
	}
	
	my $title = Properties::getLang({ lang => $email_account->getLang(), key => "title" });
	my $top_teaser = Properties::getLang({ lang => $email_account->getLang(), key => "top_teaser" });
	my $help = Properties::getLang({ lang => $email_account->getLang(), key => "help" });

	$mail_template =~ s/{title}/$title/g;
	$mail_template =~ s/{top_teaser}/$top_teaser/;
	$mail_template =~ s/{help}/$help/;

	my $content = $email_account->getFormatContent();
	
	$mail_template =~ s/{content}/$content/;

	my $cc = $email_account->getCc();
	if($cc){		
		$cc =~ s/;/,/g;
	}
	
	my $msg = MIME::Lite->new(
	             From     => 'contact@web-mining.eu',
	             To       => $email_account->getEmail(),
	             Cc       => $cc,
	             Subject  => "WebSite Checking",
	             Data     => $mail_template,
	             Type	  => "text/html; charset=iso-8859-1"
	             );
	
	$LOGGER->debug("Message send : ".$msg->send);
}
