#!/usr/bin/env perl
# Checking Perl
# Managing and storing email information
# Vanalderweireldt Benoit
# 30/12/2012

use strict;
package Email;
use Site;
use Log::Log4perl;
my $LOGGER = Log::Log4perl->get_logger("Email");

#DEFAULT LANGAGE
my $lang = "fr";

#CONSTRUCTOR
sub new {
	my $class = shift;
	my ($args) = shift;
	my $self = {};	
	bless $self, $class;
	
	#Apply default language if empty
	if(!defined $args->{lang}){
		$args->{lang} = $lang;
	}		
	
	$self->{id} = $args->{id};
	$self->{email} = $args->{email};
	$self->{nom} =	$args->{nom};
	$self->{prenom}	= $args->{prenom};
	$self->{cc}	= $args->{cc};
	$self->{frequency} = $args->{frequency};
	$self->{refSites} = ();
	$self->{lang} = $args->{lang};
	$self->{force_email} = $args->{force_email};
	
	return $self
}

#Getter for the email
sub getEmail{
	my $self = shift;
	return $self->{email};
}
#Getter for the id_site
sub getSitesRef{
	my $self = shift;
	return $self->{refSites};
}
#Add one ref for the idSites
sub addSiteRef{
	my $self = shift;
	push( @{ $self->{refSites} }, $_[0] );
}
#Getter for the cc
sub getCc{
	my $self = shift;
	return $self->{cc};
}
#Getter for lang
sub getLang{
	my $self = shift;
	return uc($self->{lang});
}
sub getForceEmail{
	my $self = shift;
	return $self->{force_email};
}
sub getId{
	my $self = shift;
	return $self->{id};
}
#Return an array of id of websites corresponding to the status
# 1) -> ref to the id hash
# 2) -> status expected
sub getSiteByStatus{
	my $self = shift;
	my ($args) = $_[0];
	
	my @refSitesByStatus;
	
	foreach my $refSite ( @{ $self->{refSites} } ){
		if( $refSite->Site::getStatus() == $args->{status} ){
			push( @refSitesByStatus, $refSite );
		}
	}
	return @refSitesByStatus;
}
sub hasOneError{
	my ($self) = shift;

	my @refSitesByStatus;
	
	foreach my $refSite ( @{ $self->{refSites} } ){
		if( $refSite->Site::getStatus() != 20 ){
			return 1;
		}
	}
	return 0;	
}
#Return the content of this email
sub getFormatContent{
	my $self = shift;

	my $content = "";
	
	$content .= $self->formatSitesCategorie({ 
		status => 1, 
		title => Properties::getLang({ lang => $self->{lang}, key => "http_error" })
	});

	$content .= $self->formatSitesCategorie({ 
		status => 2, 
		title => Properties::getLang({ lang => $self->{lang}, key => "match_keywords" })
	});
	
	$content .= $self->formatSitesCategorie({ 
		status => 3, 
		title => Properties::getLang({ lang => $self->{lang}, key => "unmatch_keywords" })
	});

	$content .= $self->formatSitesCategorie({ 
		status => 4, 
		title => Properties::getLang({ lang => $self->{lang}, key => "high_generating_time" })
	});

	$content .= $self->formatSitesCategorie({ 
		status => 6, 
		title => Properties::getLang({ lang => $self->{lang}, key => "malformed_url" })
	});

	$content .= $self->formatSitesCategorie({ 
		status => 20, 
		title => Properties::getLang({ lang => $self->{lang}, key => "check_ok" })
	});

	return $content;
}
#Format one table line for one status
sub formatSitesCategorie{
	my $self = shift;
	my ($args) = shift;
	
	my @refSitesByStatus = $self->getSiteByStatus( { sites => $args->{sites}, status => $args->{status} } );
	
	if( ! @refSitesByStatus ){
		return "";
	}
	
	my $cat_top = "<tr><td valign=\"top\"><div mc:edit=\"std_content00\"><h4 class=\"h4\">$args->{title}</h4><ul>";
	
	foreach my $site ( @refSitesByStatus ){
		$cat_top .= "<li>".format_anchor($site->getAddress())." ".$site->toString({ lang => $self->{lang} })."</li>";
	}
	
    return $cat_top."</ul></div></td></tr>";
	
}
#Format anchor link for websites
sub format_anchor{
	return "<a href='".$_[0]."'>".$_[0]."</a>";
}

sub getCountSites{
	my ($self) = shift;
	return 0 if !defined $self->{refSites};
	my $scalarRefSites = @{ $self->{refSites} };
	return $scalarRefSites;
}

1;

