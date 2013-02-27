#!/usr/bin/env perl
# Checking Perl
# Vanalderweireldt Benoit
# 4/12/2012

BEGIN{
	use File::Basename;
	eval 'use lib "'.dirname(__FILE__).'"';
	eval 'chdir "'.dirname(__FILE__).'"';
	use BSD::Resource;
	setrlimit(get_rlimits()->{RLIMIT_VMEM}, 10_500_000_000, -1) or die;
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
#
#
# Global Configuration
#
#
my $conf_path = "conf/";
my $db_target = "checking_dweb";
my $gzip = 1;
my $siteid = 0;
my $userid = 0;
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
	elsif( $arg =~ /debug=(0|1)/i ){
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
	my @row = $db->loadSiteFromId( { siteid => $siteid } );
	die("Empty Site ?") if !@row; 
	my $site_to_check = Site->newFromDbArray( { site => \@row } );
	$site_to_check->setStatus( 20 );

	$site_to_check->checkSite( { keywords => \@keywords } );

	$LOGGER->debug("Inserting operation for website : ".$site_to_check->getAddress());
	$site_to_check->save_operation( { db => $db, gzip => $gzip } );
	$db->updateSiteSatus( { status =>  $site_to_check->getStatus(), id => $site_to_check->getId() } );
	exit 0;
}

#
#
#Do we just deal with one user ?
#
#
my $emails_db;
if( $userid != 0){
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
while( my @email = $emails_db->fetchrow_array) {
		
	if (! defined $email[0] or $email[0] eq ""){
		$LOGGER->error("Empty email, go to the next one !");
		next;
	}
	$LOGGER->debug("Analizing : ".$email[0]);
	
	#if the site is activate but have no frequency we set it to 4 hours
	$email[4] = ( ( 60 / Utils::getFrequency() ) * 4 ) unless ( defined $email[4] && $email[4] ne 0 );
	#if the website don't have to be check now we go to the next one
	$LOGGER->debug("Ignore : ".$email[0]) and next unless ( Utils::getTimeSlot() % $email[4] == 0  || $userid != 0);

	$LOGGER->debug("#### Find one email account to check ".$email[0].", now will load websites associates.");
	#we a new email and save it into the global array of email
	my $emailToNotify = Email->new( { 
		email => $email[0], 
		nom => $email[1], 
		prenom => $email[2], 
		cc => $email[3], 
		frequency => $email[4],
		force_email => $email[6],
		lang => $email[7] });
	my $monitor = ( $userid == 0 )?"1":"0,1";
		
	my $websites_db = $db->loadWebsitesEmailAccount( { monitor => $monitor, user_id => $email[5] } );
	
#
#
# Multi Thread part, we will launch one thread for every site, with a maximum of $nb_process threads	
#
#	
	my $nb_process = 10;
	my $nb_compute = $websites_db->rows;
	my @running = ();
	my @Threads;
	my @sites;
	my $i = 0;
	my $total = $websites_db->rows;
	while ( my @website = $websites_db->fetchrow_array() ){
		my $site = Site->newFromDbArray( { site => \@website } );
		$site->setStatus( 20 );
		push ( @sites, $site );
		while( 1 ){
			
			@running = threads->list(threads::running);
			if( scalar @running < $nb_process ){
				$LOGGER->info("Thread ".$i." / ".$total);
				$LOGGER->debug("Start new thread -> link to ".$email[0]." : ".$website[1]);
				my $thread = threads->new( sub { $site->checkSite( { 	keywords => \@keywords, 
																		db => $db, 
																		email => $emailToNotify,
																		gzip => $gzip } ) });
				push (@Threads, $thread);
				$i++;
				if( scalar $i > $nb_process ){
					my $site_to_save = shift( @sites );
					$site_to_save->save_operation( { db => $db, gzip => $gzip } );
				}
				last;
			}
			else{
				$LOGGER->info("All thread are busy need to wait.");
				sleep(1);
			}
		}
		
	}
	foreach my $site_to_save ( @sites ){
		$site_to_save->save_operation( { db => $db, gzip => $gzip } );
	} 
	push( @emails, $emailToNotify );
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
