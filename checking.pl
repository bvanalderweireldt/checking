#!/usr/bin/env perl
# Checking Perl
# Vanalderweireldt Benoit
# 4/12/2012

use strict;
use warnings;

package Conf{
#We define the working directory to where the script is executed
use Cwd 'abs_path';
my $exec_path = abs_path($0);
$exec_path =~ s/\/\w{1,10}\.pl//;

#Method called by other workspace to get the working dir
sub getExecPath{
	return $exec_path;
}

my $test = 0;
if( $ARGV[0] eq "test" ){
	$test = 1;
}
#Are we in environment test ?
sub getEnvironment{
	if($test){
		return "-test";
	}
	else{
		return "";
	}
}
}

use lib Conf::getExecPath();
chdir Conf::getExecPath();

use Db;
use Site;
use Email;
use Properties;
use LWP::UserAgent;
use Time::HiRes qw(tv_interval gettimeofday);
use Switch;
use Net::Ping;
use WWW::Google::PageRank;
use Log::Log4perl qw(:easy);
use Mojo::DOM;
use MIME::Lite;
use File::Slurp;
use Data::Dumper;

#LOGGER
Log::Log4perl->easy_init($WARN);
DEBUG "Starting checking !";

#Generating time limit ( ms )
my $generatingTimeLimit = 15000;

#Difference between last screenshot and new one maximum in %
my $maxScreenDifference = 10;

#Connecting to db
DEBUG "Connecting to Database !";
my $db = Db->new();

#LOAD EVERY WEBSITES
DEBUG "Loading Emails !";
my $emails_db = $db->loadEmails();


#If their is no emails to check we stop here
die("No emails to check !") unless $emails_db->{NUM_OF_FIELDS} > 0;

#SETTING THE TIME FREQUENCY
my @timeData = localtime(time);
my $h = $timeData[2];
my $m = $timeData[1];
#time frequency in min
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
	my $emailToNotify = Email->new( $email[0], $email[1], $email[2], $email[3], $email[4] );

	my $websites_db = $db->loadWebsitesEmailAccount( $email[0] );

	while ( my @website = $websites_db->fetchrow_array() ){
		DEBUG "_Found one website link to ".$email[0]." : ".$website[1];
		$emailToNotify->addIdSite( $website[0] );

		if( ! exists $sites_tested{$website[1]} ){
			$sites_tested{$website[0]} = Site->new( $website[0], $website[1], $website[2], $website[3] );
		}

	}

	push( @emails, $emailToNotify );
}

#user agent used to interact with the website
DEBUG "Initializing User Agent !";
my $ua = LWP::UserAgent->new();
	$ua->agent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/536.26.14 (KHTML, like Gecko) Version/6.0.1 Safari/536.26.14');
	$ua->timeout(50);
	$ua->max_redirect(10);
	$ua->env_proxy;

#load general keywords to check in every website, trigger an alert in one of these keywords is found
DEBUG "Loading global keywords !";
my @keywords = $db->loadkeywords();

#CHECK WEBSITE
DEBUG "Starting the main loop to check every websites !";



while ( ( my $key, $_ ) = each( %sites_tested ) ){
	DEBUG "scanning ".$_->getLabel();
	#initial status = 20 -> no error
	$_->setStatus( 20 );

	#if the URL is malformed we save the status 6 (malformed) and go on to the next site
	if( $_->getLabel() !~ /^[^.].*(.)(fr|com|eu|net|org|us|gf|vn|es|biz|info|ch|ru|xxx|biz|name|pro|localhost|html)/i ){
		$_->setStatus( 6 );
		next;
	}

	#check if the http protocol is present, if not simply add it
	$_->setLabel( http_protocol( $_->getLabel ) );

	#we download the website content and save the generating time
	DEBUG "Download and get the generating time ".$_->getLabel();
	my($timeStart) = [gettimeofday()];
	my $response = $ua->get( $_->getLabel );
	$_->setContent( $response->as_string );
	my($timeElapsed) = tv_interval($timeStart, [gettimeofday()]);
	$_->setGenTime( $timeElapsed * 1000 );
	#GENERATING TIME, if the generating time is bigger than the limit
	if( $_->getGenTime() > $generatingTimeLimit ){
		$_->setStatus( 5 );
	}

	#we get the http response code from the user agent
	$_->setHttpResp( $response->code ); 	

	#if the response code is an error, and is different than 401 and 403 ( unauthorized ) we stop here, the site is down
	if( $response->is_error and ! is_unauthorized( $response->code ) ){
		$_->setStatus( 1 );
		next;
	}

	#check if in the page their is one of the global keywords
	DEBUG "Scanning for global keywords ".$_->getLabel();
	my $match_string = "";
	my $match = 0;
	foreach my $global_keyword (@keywords ){
		if ( $_->getContent() =~ /.*$global_keyword.*/i ){
			$match_string = comaConcat( $match_string, $global_keyword );
			$match = 1;
		}
	}
	if ( $match == 1 ){
		$_->setMatchKey( $match_string );
		$_->setStatus( 2 );
	}

	#check if in the page their is not one of the specified keywords
	DEBUG "Scanning for unmatch keywords ".$_->getLabel();
	$match = 1;
	my $unMatch_string = "";
	if( defined $_->getKeywords() ){
		my @keywords_specific = split ( ";", $_->getKeywords() );
		foreach my $keyword ( @keywords_specific ){
			#if it doesn't contain the given keyword
			if ( $_->getContent() !~ /.*$keyword.*/ ){
				$unMatch_string = comaConcat( $unMatch_string, $keyword );
				$match = 0;
			}
		}
	}
	if( $match == 0 ){
		$_->setUnMatchKey( $unMatch_string );
		$_->setStatus( 3 );
	}


	#GOOGLE CODE result
	DEBUG "Scanning for google analytics ".$_->getLabel();
	if ( $_->getContent =~ /.*google-analytics.com.*\/ga.js/ ){
		$_->setGoogleAnaStatus( 1 );
	}
	else{
		$_->setGoogleAnaStatus( 0 );
	}

	#PAGE RANK of the site
	DEBUG "Scanning for Google Rank ".$_->getLabel();
	my $pr = WWW::Google::PageRank->new;
#	$_->setPageRank( $pr->get( $_->getLabel(), $_->getLabel() ) );

	#Get the CMS name and version
	DEBUG "Detecting cms ".$_->getLabel();
	$_->setCms( detect_cms( $_->getContent(), $_->getLabel() ) );

	#Load the last screenshot
	DEBUG "Scanning for difference since last screen shot ".$_->getLabel();
	my $last_screen = $db->loadscreenshot(  $_->getId() );
	#compute the differenece from the previous one and the actual one
	if( defined $last_screen ){
		#my $screen_difference = compare_2_screen( $_->getContent(), $last_screen );
		#$screen_difference = ( defined $screen_difference ) ? $screen_difference : 0;
		#if( $screen_difference > $maxScreenDifference ){
		#	$_->setStatus( 4 );
		#}
	}
	DEBUG "Inserting operation for website : ".$_->getLabel();
	$db->insert_operation( { 
		id => $_->getId(), 
		content => $_->getContent(), 
		cms => $_->getCms(), 
		ping => 0, 
		genTime => $_->getGenTime(), 
		anaStatus => $_->getGoogleAnaStatus(), 
		pageRank => $_->getPageRank() });

}
DEBUG "End of the main scanning loop !";

#Loading the mail template
my $mail_template_dir = "mail_template";
my $mail_template = read_file( $mail_template_dir."/basic.html" );

my $title = Properties::getLang({ lang => "fr", key => "title" });
my $top_teaser = Properties::getLang({ lang => "fr", key => "top_teaser" });
my $help = Properties::getLang({ lang => "fr", key => "help" });

$mail_template =~ s/{title}/$title/g;
$mail_template =~ s/{top_teaser}/$top_teaser/;
$mail_template =~ s/{help}/$help/;

#DEFAULT LANGAGE
my $lang = "fr";

#SEND EMAILS
DEBUG "Starting the email loop";
foreach my $email_account ( @emails ){
	DEBUG "Preparing mail content for : ".$email_account->getEmail();
	
	my $content = "";
	
	$content .= formatSitesCategorie({ 
		email_account => $email_account, 
		sites => \%sites_tested, 
		status => 1, 
		title => Properties::getLang({ lang => $lang, key => "http_error" })
	});

	$content .= formatSitesCategorie({ 
		email_account => $email_account, 
		sites => \%sites_tested, 
		status => 2, 
		title => Properties::getLang({ lang => $lang, key => "match_keywords" })
	});
	
	$content .= formatSitesCategorie({ 
		email_account => $email_account, 
		sites => \%sites_tested, 
		status => 3, 
		title => Properties::getLang({ lang => $lang, key => "unmatch_keywords" })
	});

	$content .= formatSitesCategorie({ 
		email_account => $email_account, 
		sites => \%sites_tested, 
		status => 4, 
		title => Properties::getLang({ lang => $lang, key => "high_generating_time" })
	});

	$content .= formatSitesCategorie({ 
		email_account => $email_account, 
		sites => \%sites_tested, 
		status => 6, 
		title => Properties::getLang({ lang => $lang, key => "malformed_url" })
	});

	$content .= formatSitesCategorie({ 
		email_account => $email_account, 
		sites => \%sites_tested, 
		status => 20, 
		title => Properties::getLang({ lang => $lang, key => "check_ok" })
	});

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

sub formatSitesCategorie{
	my ($args) = @_;
	
	my @ids = $args->{email_account}->getSiteByStatus( { sites => $args->{sites}, status => $args->{status} } );
	
	if( ! @ids ){
		return "";
	}
	
	my $cat_top = "<tr><td valign=\"top\"><div mc:edit=\"std_content00\"><h4 class=\"h4\">$args->{title}</h4><ul>";
	
	foreach my $site ( @ids ){
		$cat_top .= "<li>".format_anchor($args->{sites}->{$site}->getLabel())." ".$args->{sites}->{$site}->toString({ lang => $lang })."</li>";
	}
	
    return $cat_top."</ul></div></td></tr>";
	
}


#Format anchor link for websites
sub format_anchor{
	return "<a href='".$_[0]."'>".$_[0]."</a>";
}

#ADD A HTTP PROTOCOL IF THE URL DOES NOT HAVE IT
sub http_protocol{
	if( ( $_[0] !~ /^http://///) ){
		$_[0] = "http://".$_[0] ;
	}
	return $_[0];
}

#Return true if the HTTP code is unauthorized answer
sub is_unauthorized {
	switch ( $_[0] ) {
		case [401, 403] { return 1 }
		else { return 0 }
	}
}
#Concat 2 string, if the left string is not null we add a coma between them
sub comaConcat {
	return $_[1] if( $_[0] eq "" );		
	return $_[0].",".$_[1];
}
#Detect CMS
sub detect_cms{

	my $dom = Mojo::DOM->new;
	$dom->parse( $_[0] );

	my $result;

	for my $meta ( $dom->find('meta')->each() ){
		if( defined $meta->attrs->{name} and $meta->attrs->{name} =~ /generator/i ){
			$result = $meta->attrs->{content};
		}
	}


	if ( $result eq "" ){
		return "Cannot determine the CMS";
	}
	#Drupal Detection
	if ( $result =~ /(.)*drupal(.)*/i ) {
		#Drupal 
		return "drupal";
	}
	elsif ( $result =~ /(.)*prestashop(.)*/i ){
		#Prestashop
		my $ua = new LWP::UserAgent;

		my $response = $ua->post('http://presta-version.bv-blog.fr/cgi-bin/version_presta.pl', { url => $_[1] });

		my $content = $response->content;

		return "prestashop ".$content;
	}
	elsif ( $result =~ /(.)*joomla(.)*/i ){
		#Joomla
		return "joomla";
	}
	elsif ( $result =~ /(.)*wordpress(.)*/i ){
		#Wordpress
		return "wordpress";
	}
	elsif ( $result ne "" ){
		return $result;
	}
}
#Compare 2 screen and return a % of difference (each time a line is different)
sub compare_2_screen {
	my $screen = "tmp_screen";
	my $last_screen = "tmp_last_screen";

	open ( my $screen_handler, '>', $screen);
	print $screen_handler $_[0];
	close $screen_handler;

	open ( my $last_screen_handler, '>', $last_screen);
	print $last_screen_handler $_[1];
	close $last_screen_handler;

	my $screen_nl = `cat $screen | wc -l`;
	my $last_screen_nl = `cat $last_screen | wc -l`;

	open ( $screen_handler, '<', $screen);
	open ( $last_screen_handler, '<', $last_screen);

	my $different_line = 0;
	my $total_line = 0;
	my $screen_line = "";
	my $last_screen_line = "";
	while ( $screen_line = <$screen_handler> ) {
		#if ( index( $_[1], $screen_line ) != -1 ){
		#	$different_line++;
		#}
		$total_line++;
	}

	$different_line = ( $total_line == $screen_nl ) ? $different_line : abs( $screen_nl - $total_line ) + $different_line;

	if( $total_line == 0 ){
		return 0;}
	else{
		return ceil ( ( $different_line / $total_line ) * 100 );
	}
} 	 	

