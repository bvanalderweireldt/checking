#!/usr/bin/env perl
# Vanalderweireldt Benoit
# 21/02/2013

BEGIN{
	use File::Basename;
	eval 'chdir "'.dirname(__FILE__).'"';
	eval 'use lib "../"';
}

use Db;

my $idoperation = $ARGV[0];

die("No operation id provided !") if ! defined $idoperation;

my $db_target = "checking_dweb";

my $db = Db->new( { db_target => $db_target } );

my $content = $db->loadContentOperationId({ id => $idoperation });

if( $content =~ /^\d+$/ ){
	$content = $db->loadContentOperationId({ id => $content });
}

print $content;


