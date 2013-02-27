#!/usr/bin/env perl
# Checking Perl
# Managing and storing site information
# Vanalderweireldt Benoit
# 10/12/2012

use strict;
package Site;

use Data::Dumper;
use Switch;
use LWP::UserAgent;
use Time::HiRes qw(tv_interval gettimeofday);
use WWW::Google::PageRank;
use Mojo::DOM;
use Socket;
use Properties;
use  Log::Log4perl;
my $LOGGER = Log::Log4perl->get_logger("Site");

my $protocol = "http://";

my $ua = LWP::UserAgent->new();
	$ua->agent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/536.26.14 (KHTML, like Gecko) Version/6.0.1 Safari/536.26.14');
	$ua->timeout(50);
	$ua->max_redirect(10);
	$ua->env_proxy;

#Generating time limit ( ms )
my $generatingTimeLimit = 15000;

#Basic Constructor
sub new {
	my ($class) = shift;
	my ($args) = shift;

	my $self = {};	
	bless $self, $class;
		
	$self->{id}	= $args->{id};

	$self->{address} = $args->{address};
	$self->{address} =~ s/^http(s)?://i;
	$self->{address} =~ s/\/$//;
	$self->{keywords} =	$args->{keywords};
	$self->{status}	= $args->{status};
	$self->{googleAnaStatus} = 0;
	$self->{cms} = "";
	$self->{unMatchKey} = "";
	$self->{matchKey} = "";
	$self->{ip} = 0;

	return $self
}

#Consctructor from DB array 
#1) -> id
#2) -> address
#3) -> keywords
#4) -> status
sub newFromDbArray{
	my ($class) = shift;
	my ($args) = shift;

	my $self = {};
	bless $self, $class;

	$self->{id} = @{$args->{site}}[0];
	$self->{address} = @{$args->{site}}[1];
	$self->{address} =~ s/^http(s)?:\/\///i;
	$self->{address} =~ s/\/$//;
	$self->{keywords} = @{$args->{site}}[2];
	$self->{status} = @{$args->{site}}[3];
	$self->{googleAnaStatus} = 0;
	$self->{cms} = "";
	$self->{unMatchKey} = "";
	$self->{matchKey} = "";
	$self->{ip} = 0;

	return $self;
}
sub toString{
	my ($self) = @_;
	my ($args) = $_[1];
	switch( $self->{status} ){
	
	case 1 {
		return Properties::getLang( { lang => $args->{lang}, key => "http_error" } )." (".$self->{httpResp}.")";
	}
	case 2 {
		return Properties::getLang( { lang => $args->{lang}, key => "match_keywords" } )." (".$self->{matchKey}.")";
	}
	case 3 {
		return Properties::getLang( { lang => $args->{lang}, key => "unmatch_keywords" } )." (".$self->{unMatchKey}.")";
	}
	case 5 {
		return Properties::getLang( { lang => $args->{lang}, key => "high_generating_time" } )." (".$self->{genTime}.")";
	}
	case 6 {
		return Properties::getLang( { lang => $args->{lang}, key => "malformed_url" } )." (".$self->{label}.")";
	}
	case 20 {
		return Properties::getLang( { lang => $args->{lang}, key => "check_ok" } );
	}
	}
}
#Check if the web site address is correct or not
sub validateUrl{
	my ($self) = shift;
	if( $self->getAddress() !~ /([^.]*(.)[a-zA-Z]+)|((\d){0,3}\.{0,3}\.{0,3}\.{0,3}(\/~.*)?)/i ){
		$self->{status} = 6 ;
		return 0;
	}
	return 1;
}
#Download the content of the website and save the generating time of the page
sub download{
	my ($self) = shift;

	my($timeStart) = [gettimeofday()];
	$LOGGER->debug($protocol.$self->{address});
	my $response = $ua->get( $protocol.$self->{address} );
	$self->{content} = $response->content ;
	my($timeElapsed) = tv_interval($timeStart, [gettimeofday()]);
	$self->{genTime} = ( $timeElapsed * 1000 );

	#GENERATING TIME, if the generating time is bigger than the limit
	if( $self->{genTime} > $generatingTimeLimit ){
		$self->{status} = 5;
	}

	#we get the http response code from the user agent
	$self->{httpResp} = $response->code; 	

	#if the response code is an error, and is different than 401 and 403 ( unauthorized ) we stop here, the site is down
	if( $response->is_error and ! is_unauthorized( $response->code ) ){
		$self->{status} = 1;
		return 0;
	}
	return 1;
}

#Scan for the presence of global keyword
sub scanGLobalKeywords{
	my ($self) = shift;
	my ($args) = shift;

	foreach my $global_keyword ( @{$args->{keywords}} ){
		if ( $self->{content} =~ /.*$global_keyword.*/i ){
			$self->{matchKey} = comaConcat( $self->{matchKey}, $global_keyword );
			$self->{status} = 2;
		}
	}
}
#scan for expected keywords that doesn't match
sub scanUnMatchKeywords{
	my ($self) = shift;

	if( defined $self->{keywords} ){
		my @keywords_specific = split ( ";", $self->{keywords} );
		foreach my $keyword ( @keywords_specific ){
			#if it doesn't contain the given keyword
			if ( $self->{content} !~ /.*$keyword.*/ ){
				$self->{unMatchKey} = comaConcat( $self->{unMatchKey}, $keyword );
				$self->{status} = 3;
			}
		}
	}
}
#Scan for Google Analytic Presence
sub scanForGoogleAnalytic{
	my ($self) = shift;
	if ( $self->{content} =~ /.*google-analytics.com.*\/ga.js/ ){
		$self->{googleAnaStatus} = 1;
	}
	else{
		$self->{googleAnaStatus} = 0;
	}
}
#Get the google page rank
sub computeGooglePageRank{
	my ($self) = shift;
	my $pr = WWW::Google::PageRank->new;
	$self->{pageRank} = scalar($pr->get($protocol.$self->{address}, "\n" ));
}
#Try to guess if the site is running a CMS
sub detectCms{
	my ($self) = shift;
	my $dom = Mojo::DOM->new;
	$dom->parse( $self->{content} );

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
		$result = "drupal";
	}
	elsif ( $result =~ /(.)*prestashop(.)*/i ){
		#Prestashop
		my $ua = new LWP::UserAgent;

		my $response = $ua->post('http://presta-version.bv-blog.fr/cgi-bin/version_presta.pl', { url => $self->{address} });

		my $content = $response->content;

		$result = "prestashop ".$content;
	}
	elsif ( $result =~ /(.)*joomla(.)*/i ){
		#Joomla
		$result = "joomla";
	}
	elsif ( $result =~ /(.)*wordpress(.)*/i ){
		#Wordpress
		$result = "wordpress";
	}
	$self->{cms} = $result;
}
sub computeIpFromAddress{
	my ($self) = shift;

	my $ip = gethostbyname($self->{address});
	if (defined $ip) {
		$self->{ip} = inet_ntoa($ip);
	}
}
sub pingFromIP{
	my ($self) = shift;
	my $ping_cmd = `ping $self->{ip} -c 1 -w 10`;
	if( $ping_cmd =~ /mdev\s=\s(\d+\.\d+)\//){
		$self->{ping} = $1;
	}
	else{
		$self->{ping} = -1;
	}
}
sub checkSite{
	my ($self) = shift;
	my ($args) = shift;
	
	$LOGGER->debug("Start check for : ".$self->{address});
	$LOGGER->debug("Validate Url");
	return 0 if !$self->validateUrl();
	$LOGGER->debug("Download site");
	return 0 if !$self->download();
	$LOGGER->debug("Scan Global keywords");
	$self->scanGLobalKeywords({keywords => $args->{keywords}});
	$LOGGER->debug("Scan Expected keywords");
	$self->scanUnMatchKeywords();
	$LOGGER->debug("Scan Google Analytic");
	$self->scanForGoogleAnalytic();
	$LOGGER->debug("Detect CMS");
	$self->detectCms();
	$LOGGER->debug("Compute Page Rank");
	$self->computeGooglePageRank();
	$LOGGER->debug("Get ip address");
	$self->computeIpFromAddress();
	$LOGGER->debug("Server Ping time");
	$self->pingFromIP();
		
	$args->{email}->addSiteRef( $self );
	return 1;
}
#Concat 2 string, if the left string is not null we add a coma between them
sub comaConcat {
	return $_[1] if( $_[0] eq "" );		
	return $_[0].",".$_[1];
}
#Check if it's an unauthrorized status
sub is_unauthorized{
	if( $_[0] == 401 || $_[0] == 403 ){
		return 1;
	}
	return 0;	
}
#Save operation in DB
sub save_operation{
	my ($self) = shift;
	my ($args) = shift;
	
	$self->toggleContentOrIdOperation( { db => $args->{db} } );

	$args->{db}->insert_operation( { 
		id => $self->getId(), 
		content => $self->getContent(), 
		cms => $self->getCms(), 
		ping => $self->{ping}, 
		genTime => $self->getGenTime(), 
		googleAnaStatus => $self->getGoogleAnaStatus(), 
		pageRank => $self->getPageRank(),
		matchKey => $self->getMatchKey(),
		unMatchKey => $self->getUnMatchKey(),
		gzip => $args->{gzip},
		status => $self->getStatus(),
		ip => $self->{ip} });
}
#Toggle the content to an operation id if it haven't changed since last checking
sub toggleContentOrIdOperation{
	my ($self) = shift;
	my ($args) = shift;
	
	my $last_content = $args->{db}->loadLastContentFromSiteid( { siteid => $self->{id} } );
	my $id_content = "";
	
	#If the content refer to a id
	if( $last_content =~ /^\d+$/ ){
		$id_content = $last_content;
		$last_content = $args->{db}->loadContentOperationId( { id => $id_content } );
	}
	
	if( $last_content ne $self->{content} ){
		$LOGGER->debug("New content will be stored in DB !");
	}
	else{
		if( $id_content eq "" ){
			$id_content = $args->{db}->loadLastOperationIdFromSiteid(  { siteid => $self->{id} } );
		}
		$LOGGER->debug("Content haven't changed will make reference to the content already saved ! ($id_content)");
		$self->{content} = $id_content;
	}
}
#Setter for the status
sub setStatus{
	my $self = shift;
	$self->{status} = $_[0];
}
#Setter for the page content
sub setContent{
	my $self = shift;
	$self->{content} = $_[0];
}
#Setter for the Generating Time
sub setGenTime{
	my $self = shift;
	$self->{genTime} = $_[0];
}
#Setter for the matching keywords
sub setMatchKey{
	my $self = shift;
	$self->{matchKey} = $_[0];
}
#Getter for the matching keywords
sub getMatchKey{
	my $self = shift;
	return $self->{matchKey};
}
#Setter for the unmatching keywords
sub setUnMatchKey{
	my $self = shift;
	$self->{unMatchKey} = $_[0];
}
#Getter for the unmatching keywords
sub getUnMatchKey{
	my $self = shift;
	return $self->{unMatchKey};
}
#Setter for the google analytic code status
sub setGoogleAnaStatus{
	my $self = shift;
	$self->{googleAnaStatus} = $_[0];
}
#Getter for the google analytic code status
sub getGoogleAnaStatus{
	my $self = shift;
	return $self->{googleAnaStatus};
}
#Setter for the Http response code
sub setHttpResp{
	my $self = shift;
	$self->{httpResp} = $_[0];
}
#Getter for the Http response code
sub getHttpResp{
	my $self = shift;
	return $self->{httpResp};
}
#Setter for the Page Rank
sub setPageRank{
	my $self = shift;
	$self->{pageRank} = $_[0];
}
#Getter for the Page Rank
sub getPageRank{
	my $self = shift;
	return $self->{pageRank};
}
#Setter for cms label
sub setCms{
	my $self = shift;
	$self->{cms} = $_[0];
}
#Getter for the cms label
sub getCms{
	my $self = shift;
	return $self->{cms};
}
#Getter for the Generating Time
sub getGenTime{
	my $self = shift;
	return $self->{genTime};
}
#Getter for the page content
sub getContent{
	my $self = shift;
	return $self->{content};
}
#Getter for the status
sub getStatus{
	my $self = shift;
	return $self->{status};
}
#Getter for the id
sub getId{
	my $self = shift;
	return $self->{id};
}
#Getter for the label
sub getAddress{
	my $self = shift;
	return $self->{address};
}
#Setter for the label
sub setLabel{
	my $self = shift;
	$self->{label} = $_[0];
}
#Getter for the keywords
sub getKeywords{
	my $self = shift;
	return $self->{keywords};
}
1;
