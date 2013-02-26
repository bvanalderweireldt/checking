#!/usr/bin/perl

#Vanalderweireldt Benoit 5/02/2013

package Properties;

use strict;
use warnings;

use Log::Log4perl;
my $LOGGER = Log::Log4perl->get_logger("Props");

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
	$LOGGER->debug("Try to find properties messages, lang : ".$args->{lang}.", key : ".$args->{key});
	if( !$args->{lang} ){
		$LOGGER->error("getProp cannot get prop without lang !");
		return;
	}
	if( !$args->{key} ){
		$LOGGER->error("getProp cannot get prop without key !");
		return;		
	}
	
	if( $args->{lang} =~ /fr/i ){
		my $lang_key = $frLang->getProperty( $args->{key} );
		$LOGGER->debug("Found : ".$lang_key);	
	}
	elsif( $args->{lang} =~ /eng/i ){
		my $lang_key = $engLang->getProperty( $args->{key} );	
		$LOGGER->debug("Found : ".$lang_key);	
	}
	else{
		$LOGGER->error("Cannot find properties messages, lang : ".$args->{lang}.", key : ".$args->{key});
	}
}
1
