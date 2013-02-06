#!/usr/bin/perl

#Vanalderweireldt Benoit 5/02/2013

package Properties;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($WARN);

use Config::Properties;

#LOAD ENGLISH LANG
open PROPS_ENG, "< lang/eng.lang"
	or die "unable to open configuration file";
my $engLang = new Config::Properties();
$engLang->load(*PROPS_ENG);

#LOAD ENGLISH LANG
open PROPS_FR, "< lang/fr.lang"
	or die "unable to open configuration file";
my $frLang = new Config::Properties();
$frLang->load(*PROPS_FR);

sub getLang{
	
	my ($args) = @_;
	
	if( !$args->{lang} ){
		ERROR "getProp cannot get prop without lang !";
		return;
	}
	if( !$args->{key} ){
		ERROR "getProp cannot get prop without key !";
		return;		
	}
	
	if( $args->{lang} eq "fr" ){
		return $frLang->getProperty( $args->{key} );	
	}
	elsif( $args->{lang} eq "eng" ){
		return $engLang->getProperty( $args->{key} );	
	}
}
1
