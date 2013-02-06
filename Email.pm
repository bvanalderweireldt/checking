#!/usr/bin/env perl
# Checking Perl
# Managing and storing email information
# Vanalderweireldt Benoit
# 30/12/2012

use strict;
package Email;

#CONSTRUCTOR
sub new {
	my ( $class, $email, $nom, $prenom, $cc, $frequency ) = @_;
	my $self = {};	
	bless $self, $class;
		
	$self->{email} = $email;
	$self->{nom} =	$nom;
	$self->{prenom}	= $prenom;
	$self->{cc}	= $cc;
	$self->{frequency} = $frequency;
	$self->{idSites} = ();

	return $self
}

#Getter for the email
sub getEmail{
	my $self = shift;
	return $self->{email};
}
#Getter for the id_site
sub getIdSites{
	my $self = shift;
	return $self->{idSites};
}
#Add one ref for the idSites
sub addIdSite{
	my $self = shift;
	push( @{ $self->{idSites} }, $_[0] );
}
#Getter for the cc
sub getCc{
	my $self = shift;
	return $self->{cc};
}
#Return an array of id of websites corresponding to the status
# 1) -> ref to the id hash
# 2) -> status expected
sub getSiteByStatus{
	my $self = shift;
	my ($args) = $_[0];
	
	my @ids;
	
	foreach my $id ( @{ $self->{idSites} } ){
		if( %{ $args->{sites} }->{$id}->getStatus() == $args->{status} ){
			push( @ids, $id );
		}
	}
	return @ids;
}
1;

