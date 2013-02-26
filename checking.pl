#!/usr/bin/env perl
# Checking Perl
# Vanalderweireldt Benoit
# 4/12/2012

use strict;
use warnings;
use Db;
use Site;
use Email;
use Time::HiRes qw(tv_interval gettimeofday);
use MIME::Lite;
use File::Slurp;
use Log::Log4perl;

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

BEGIN{
	use File::Basename;
	eval 'use lib "'.dirname(__FILE__).'"';
	eval 'chdir "'.dirname(__FILE__).'"';
}


foreach my $arg ( @ARGV ){
	if( $arg =~ /db=\w+/i ){
		$db_target = extractArg({ arg => $arg });
	}
	elsif( $arg =~ /gzip=(0|1)/i ){
		$gzip = extractArg({ arg => $arg });
	}
	elsif( $arg =~ /siteid=\d+/i){
		$siteid = extractArg({ arg => $arg })
	}
	elsif( $arg =~ /userid=\d+/i){
		$userid = extractArg({ arg => $arg })
	}
	elsif( $arg =~ /debug=(0|1)/i ){
		$log = $conf_path."log4p-debug.conf";
	}
	elsif( $arg =~ /-h/i ){
		displayHelp();
		exit 0;
	}
	else{
		die("Error wrong argument passed, type -h to see help !");
	}
}
sub extractArg{
	my ($args) = shift;
	$args->{arg} =~ s/^\w+=//;
	return  $args->{arg};
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
# Display Help
#
#
sub displayHelp{
	print "Checking Help :
	db={db+username} default=checkingweb
	gzip={0 or 1} gzip compression for screenshot default=1
	siteid={idsite} check only one site
	userid={userid} do a full scan for a given user
	debug={0 or 1} activate debug output default =1\n";
}

$LOGGER->debug("Starting checking !");

#Connecting to db
$LOGGER->info("Connecting to Database !");
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

#If their is no emails to check we stop here
$LOGGER->info("No email to check !") and exit 0 unless scalar($emails_db) > 0;

#SETTING THE TIME FREQUENCY
my @timeData = localtime(time);
my $h = $timeData[2];
my $m = $timeData[1];
#Time frequency in min
my $frequency = 30;
my $t = int( $m / $frequency ) + ( $h * ( 60 / $frequency ) );

#SITES HASH by SITE ID
my %sites_tested;

#Emails account array
my @emails;

#CHECK IF SOME emails account HAVE TO BE CHECK
$LOGGER->debug("Scanning to find what emails account have to be check !");
while( my $email = ( shift(@$emails_db) ) ) {
	if (! defined @{$email}[0] or @{$email}[0] eq ""){
		$LOGGER->error("Empty email, go to the next one !");
		next;
	}
	$LOGGER->debug("Analizing : ".@{$email}[0]);
	
	#if the site is activate but have no frequency we set it to 4 hours
	@{$email}[4] = ( ( 60 / $frequency ) * 4 ) unless ( defined @{$email}[4] && @{$email}[4] ne 0 );
	#if the website don't have to be check now we go to the next one
	$LOGGER->debug("Ignore : ".@{$email}[0]) and next unless ( $t % @{$email}[4] == 0  || $userid != 0);

	$LOGGER->debug("#### Find one email account to check ".@{$email}[0].", now will load websites associates.");
	#we a new email and save it into the global array of email
	my $emailToNotify = Email->new( { 
		email => @{$email}[0], 
		nom => @{$email}[1], 
		prenom => @{$email}[2], 
		cc => @{$email}[3], 
		frequency => @{$email}[4],
		force_email => @{$email}[6],
		lang => @{$email}[7] });
	my $monitor = ( $userid == 0 )?"1":"0,1";

	my $websites_db = $db->loadWebsitesEmailAccount( { monitor => $monitor, user_id => @{$email}[5] } );
		
	while ( my @website = $websites_db->fetchrow_array() ){
		$LOGGER->debug("_Found one website link to ".@{$email}[0]." : ".$website[1]);

		if( ! exists $sites_tested{$website[1]} ){
			$sites_tested{$website[0]} = Site->newFromDbArray( { site => \@website } );
		}

		$emailToNotify->addSiteRef( $sites_tested{$website[0]} );

	}

	push( @emails, $emailToNotify );
}

#CHECK WEBSITE
$LOGGER->info("Starting the main loop to check every websites, must scan : ".scalar(%sites_tested));

while ( ( my $key, $_ ) = each( %sites_tested ) ){
	$LOGGER->debug("scanning ".$_->getAddress());
	#initial status = 20 -> no error
	$_->setStatus( 20 );

	$_->checkSite( { keywords => \@keywords } );

	$LOGGER->debug("Inserting operation for website : ".$_->getAddress());
	$_->save_operation( { db => $db, gzip => $gzip } );
}
$LOGGER->debug("End of the main scanning loop !");


#SEND EMAILS
$LOGGER->debug("Starting the email loop, must scan : ".scalar(@emails)." email(s)");
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

	my $local_mail_template = $mail_template;
	$local_mail_template =~ s/{content}/$content/;
	
	my $cc = $email_account->getCc();
	if($cc){		
		$cc =~ s/;/,/g;
	}
	
	my $msg = MIME::Lite->new(
	             From     => '',
	             To       => $email_account->getEmail(),
	             Cc       => $cc,
	             Subject  => "WebSite Checking",
	             Data     => $local_mail_template,
	             Type	  => "text/html; charset=iso-8859-1"
	             );
	
	$LOGGER->debug("Message send : ".$msg->send);
}
