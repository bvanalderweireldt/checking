#!/usr/bin/env perl
# Checking Perl
# Managing and storing site information
# Vanalderweireldt Benoit
# 10/12/2012

use strict;
package Site;

use Switch;
use Properties;

#CONSTRUCTOR
sub new {
	my ( $class, $id, $label, $keywords, $status ) = @_;
	my $self = {};	
	bless $self, $class;
		
	$self->{id}			=		$id;
	$self->{label} 		=		$label;
	$self->{keywords}	=		$keywords;
	$self->{status}		=		$status;
	
	return $self
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
sub getLabel{
	my $self = shift;
	return $self->{label};
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
