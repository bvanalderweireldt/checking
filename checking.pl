#!/usr/bin/env perl
# Checking Perl
# Vanalderweireldt Benoit
# 4/12/2012

use strict;
use warnings;

BEGIN{
	use File::Basename;
	eval 'use lib "'.dirname(__FILE__).'"';
	eval 'chdir "'.dirname(__FILE__).'"';
}

use Db;
use Site;
use Email;
use Time::HiRes qw(tv_interval gettimeofday);
use Log::Log4perl qw(:easy);
use MIME::Lite;
use File::Slurp;

#LOGGER
Log::Log4perl->easy_init($INFO);
DEBUG "Starting checking !";

my $db = "checkingweb";
my $gzip = 1;
my $siteid = 0;
foreach my $arg ( @ARGV ){
	if( $arg =~ /db=\w+/i ){
		$db = extractArg({ arg => $arg });
	}
	elsif( $arg =~ /gzip=(0|1)/i ){
		$gzip = extractArg({ arg => $arg });
	}
	elsif( $arg =~ /siteid=\d+/i){
		$siteid = extractArg({ arg => $arg })
	}
	elsif( $arg =~ /-h/i ){
		displayHelp();
		return 1;
	}
	else{
		die("Error wrong argument passed, type -h to see help !");
	}
}

sub displayHelp{
	print "Checking Help :\n
	db={db+username} default=checkingweb\n
	gzip={0 or 1} gzip compression for screenshot default=1
	idsite={idsite} check only one site";
	
}

sub extractArg{
	my ($args) = shift;
	$args->{arg} =~ s/^\w+=//;
	return  $args->{arg};
}

#Connecting to db
INFO "Connecting to Database !";
my $db = Db->new($db);

#Enable String gZip for site content in database
my $db_content_gZip = 1;
if( defined $ARGV[1] && $ARGV[1] eq 'dgzip' ){
	$db_content_gZip = 0; 
	INFO "# gZip disable !";
}

#LOAD EVERY WEBSITES
DEBUG "Loading Emails !";
my $emails_db = $db->loadEmails();

#If their is no emails to check we stop here
die("No emails to check !") unless $emails_db->{NUM_OF_FIELDS} > 0;

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
DEBUG "Scanning to find what emails account have to be check !";
while ( my @email = $emails_db->fetchrow_array() ) {
	
	DEBUG "Analizing : ".$email[0];
	
	#if the site is activate but have no frequency we set it to 4 hours
	$email[4] = ( ( 60 / $frequency ) * 4 ) unless ( defined $email[4] && $email[4] ne 0 );
	#if the website don't have to be check now we go to the next one
	next unless ( $t % $email[4] == 0 );

	DEBUG "#### Find one email account to check ".$email[0].", now will load websites associates.";

	#we a new email and save it into the global array of email
	my $emailToNotify = Email->new( { 
		email => $email[0], 
		nom => $email[1], 
		prenom => $email[2], 
		cc => $email[3], 
		frequency => $email[4]);

	my $websites_db = $db->loadWebsitesEmailAccount( $email[0] );

	while ( my @website = $websites_db->fetchrow_array() ){
		DEBUG "_Found one website link to ".$email[0]." : ".$website[1];

		if( ! exists $sites_tested{$website[1]} ){
			$sites_tested{$website[0]} = Site->newFromDbArray( { site => \@website } );
		}

		$emailToNotify->addSiteRef( $sites_tested{$website[0]} );

	}

	push( @emails, $emailToNotify );
}


#load general keywords to check in every website, trigger an alert in one of these keywords is found
DEBUG "Loading global keywords !";
my @keywords = $db->loadkeywords();

#CHECK WEBSITE
DEBUG "Starting the main loop to check every websites !";

while ( ( my $key, $_ ) = each( %sites_tested ) ){
	DEBUG "scanning ".$_->getAddress();
	#initial status = 20 -> no error
	$_->setStatus( 20 );

	$_->checkSite( { keywords => \@keywords } );

	DEBUG "Inserting operation for website : ".$_->getAddress();
	$db->insert_operation( { 
		id => $_->getId(), 
		content => $_->getContent(), 
		cms => $_->getCms(), 
		ping => 0, 
		genTime => $_->getGenTime(), 
		anaStatus => $_->getGoogleAnaStatus(), 
		pageRank => $_->getPageRank(),
		gzip => $db_content_gZip });

}
DEBUG "End of the main scanning loop !";

#Loading the mail template
my $mail_template_dir = "mail_template";
my $mail_template = read_file( $mail_template_dir."/basic.html" );

#SEND EMAILS
DEBUG "Starting the email loop";
foreach my $email_account ( @emails ){
	DEBUG "Preparing mail content for : ".$email_account->getEmail();
	
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
	             From     => 'checking@webmining.eu',
	             To       => $email_account->getEmail(),
	             Cc       => $cc,
	             Subject  => "WebSite Checking",
	             Data     => $local_mail_template,
	             Type	  => "text/html; charset=iso-8859-1"
	             );
	
	$msg->send;
}
