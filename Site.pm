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
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Properties;

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

	$args->{address} =~ s/^http(s)?://i;
	$self->{address} = $args->{address};
	$self->{keywords} =	$args->{keywords};
	$self->{status}	= $args->{status};
	
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
	$self->{keywords} = @{$args->{site}}[2];
	$self->{status} = @{$args->{site}}[3];

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
	if( $self->getAddress() !~ /^[^.]*(.)[a-zA-Z]+/i ){
		$self->{status} = 6 ;
		return 0;
	}
	return 1;
}
#Download the content of the website and save the generating time of the page
sub download{
	my ($self) = shift;

	my($timeStart) = [gettimeofday()];
	my $response = $ua->get( $protocol.$self->{address} );
	$self->{content} = $response->as_string ;
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

	$self->{matchKey} = "";
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

	$self->{unMatchKey} = "";
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
	$self->{pageRank} = $pr->get( $self->{address}, $self->{address} );
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
sub checkSite{
	my ($self) = shift;
	my ($args) = shift;

	return 0 if !$self->validateUrl();
	return 0 if !$self->download();
	$self->scanGLobalKeywords({keywords => $args->{keywords}});
	$self->scanUnMatchKeywords();
	$self->scanForGoogleAnalytic();
	$self->detectCms();
	$self->computeGooglePageRank();

}
#Concat 2 string, if the left string is not null we add a coma between them
sub comaConcat {
	return $_[1] if( $_[0] eq "" );		
	return $_[0].",".$_[1];
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
