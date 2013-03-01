#!/usr/bin/env perl
# Checking Perl
# Vanalderweireldt Benoit
# 27/02/2012

use DBI;
use strict;
use utf8;
my $db_s_dsn = "DBI:mysql:database=checkingweb;host=localhost;port=3306;mysql_socket=/var/lib/mysql/mysql.sock";
my $db_s = DBI->connect($db_s_dsn, "root", $ARGV[0] ) or die "Cannot connect to Mysql";

my $db_d_dsn = "DBI:mysql:database=checking_dweb;host=localhost;port=3306;mysql_socket=/var/lib/mysql/mysql.sock";
my $db_d = DBI->connect($db_s_dsn, "root", $ARGV[0] ) or die "Cannot connect to Mysql";
my $insert_site_q = "INSERT INTO checking_dweb.checking_front_site 
	(id, user_id, address, monitor, keywords, date_added, status) 
	VALUES (NULL, ".$ARGV[1].", ?, ?, ?, NOW(), '20')";
my $test_exist_q = "select * from checking_dweb.checking_front_site where address like";

my $load_all_sites = "select * from monitorServer_site";
my $db_sites_s = $db_s->prepare( $load_all_sites );
$db_sites_s->execute() or die "Cannot load sites !";

my $limit=0;

while ( my @site = $db_sites_s->fetchrow_array() ){
	
	my $test = $db_d->prepare( $test_exist_q." '%".$site[1]."%'");
	$test->execute();
	if( $test->fetchrow_array() ){
		print "Doublon : ".$site[1]."\n";
	}
	else{		
		my $insert_site = $db_d->prepare( $insert_site_q );
		$site[4] = ( ! defined $site[4] ) ? '':$site[4];
		$insert_site->execute( $site[1], $site[5], $site[4] );
	}
	
	if ( $limit > $ARGV[2] ){
		last;
	}
	$limit++;
}
print $limit."\n";
