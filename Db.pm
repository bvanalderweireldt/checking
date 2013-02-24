#!/usr/bin/env perl
# Checking Perl
# DATABASE ACCESS AND QUERY CLASS
# Vanalderweireldt Benoit
# 01/08/2012

use DBI;
use strict;
package Db;

use Log::Log4perl qw(:easy);

#TABLE DESCRIPTION
my $TABLE_SITE = "checking_front_site"; 
my $TABLE_KEYWORDS = "checking_front_keywords";
my $TABLE_OPERATION = "checking_front_operation";
my $TABLE_USER = "auth_user";
my $TABLE_USER_PROFILE = "checking_front_userprofile";
#CONSTRUCTOR
sub new {
	my ($class) = shift;
	my ($args) = shift;
	
	my $target = $args->{db_target};
	
	INFO "### Database Selected : $target";
	
	my $self = {};	
	bless $self, $class;
		
	$self->{_dsn}		=	"DBI:mysql:database=$target;host=localhost;port=3306;mysql_socket=/var/lib/mysql/mysql.sock";
		
	$self->{_db} 		=	DBI->connect($self->{_dsn}, "checking_dweb", "P4kWbX0sE0QnOQwW66pnE8NTX8NWuL") or die "Cannot connect to Mysql";
	
	return $self
}
#Load Email that have to be test,based on frequency
sub loadEmails {
	my $self = shift;
	#SQL Query load every emails
	my $load_all_emails_query = "select email, first_name, last_name, cc, frequency, user_id from $TABLE_USER as a right join $TABLE_USER_PROFILE as up on a.id = up.user_id";
	my $db_emails = $self->{_db}->prepare( $load_all_emails_query );
	$db_emails->execute() or die "Cannot load emails !";
	return $db_emails;
}
#LOAD ACTIVATE WEBSITES OF A GIVEN EMAIL ACCOUNT
sub loadWebsitesEmailAccount {
	my ($self) = shift;
	my ($args) = shift;
	#SQL Query load all websites
	my $load_websites_query = "select id, address, keywords, status 
	from $TABLE_SITE  where monitor=1 and user_id = ?";
	my $db_websites = $self->{_db}->prepare( $load_websites_query );
	$db_websites->execute( $args->{user_id} ) or die "Cannot load websites !";
	return $db_websites;
}
sub loadSiteFromId{
	my ($self) = shift;
	my ($args) = shift;
	#Query to load one site
	my $loadSiteFromId = "select id, address, keywords, status from $TABLE_SITE where id = ?"; 
	my $db_site = $self->{_db}->prepare( $loadSiteFromId );
	$db_site->execute( $args->{siteid} ) or die "Cannot load site !";
	return $db_site->fetchrow_array();	
}
sub updateSiteSatus{
	my ($self) = shift;
	my ($args) = shift;
	#Query to update status
	my $updateSiteStatus = "update $TABLE_SITE set status = ? where id = ?"; 
	my $db_updatesite = $self->{_db}->prepare( $updateSiteStatus );
	$db_updatesite->execute( $args->{status}, $args->{id} )
}
#LOAD GLOBAL KEYWORDS
sub loadkeywords {
	my $self = shift;
	#SQL Query load all suspicious keywords 
	my $load_suspiciouskeywords_query = "select label from $TABLE_KEYWORDS";
	my $db_keywords = $self->{_db}->prepare( $load_suspiciouskeywords_query );
	$db_keywords->execute();
	my @keywords;
	while( my @keyword = $db_keywords->fetchrow_array ){
		push( @keywords, $keyword[0]) if ($keyword[0] ne "");
	}
	return @keywords;
}
#Query load the last recorded content
sub loadLastContentFromSiteid {
	my ($self) = shift;
	my ($args) = shift;
	my $load_last_screenshot = "select content from $TABLE_OPERATION where site_id = ? order by date desc limit 0,1;";
	my ( $content ) = $self->{_db}->selectrow_array( $load_last_screenshot, undef, $args->{siteid} );

	use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
	my $uncompressedScreenshot;

	gunzip \$content => \$uncompressedScreenshot;
	
	return $uncompressedScreenshot;
}
sub loadLastOperationIdFromSiteid {
	my ($self) = shift;
	my ($args) = shift;
	my $load_last_screenshot = "select id from $TABLE_OPERATION where site_id = ? order by date desc limit 0,1;";
	my ( $id ) = $self->{_db}->selectrow_array( $load_last_screenshot, undef, $args->{siteid} );

	return $id;
}
#INSERT ONE OPERATION IN DB
sub insert_operation {
	my $self = shift;
	my ($args) = $_[0];

	my $insert_operation = "INSERT INTO $TABLE_OPERATION 
			   (id   , date  ,  content, unMatchKeywords, matchKeywords, googleAna ,cms , site_id, genTime, pageRank, status, ip, ping )
		VALUES (NULL , NOW() ,  ?      ,  ?             , ?            , ?         , ?  , ?      , ?      , ?		, ?		, ?	, ?);";
	my $db_keywords = $self->{_db}->prepare( $insert_operation );

	if( $args->{gzip} ){
		use IO::Compress::Gzip qw(gzip $GzipError) ;
		my $content_compress;
		
		gzip \$args->{content} => \$content_compress;
		
		use bytes;
		my $gain = (length($args->{content}) - length($content_compress)) / 1000;
		INFO "gZip saved ".$gain." kBytes !";
		$args->{content} = $content_compress;	
	} 
	$db_keywords->execute( $args->{content}, $args->{unMatchKey}, $args->{matchKey}, $args->{googleAnaStatus}, 
		$args->{cms}, $args->{id}, $args->{genTime}, $args->{pageRank}, $args->{status}, $args->{ip}, $args->{ping});
}
#LOAD OPERATION FROM ID
sub loadContentOperationId {
	my $self = shift;
	my ($args) = shift;
	
	my $loadScreenShotByOperationId = "select content from $TABLE_OPERATION where id = ".$args->{id};
	my ( $content ) = $self->{_db}->selectrow_array( $loadScreenShotByOperationId );
	
	use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
	my $uncompressedScreenshot;

	gunzip \$content => \$uncompressedScreenshot;

	return $uncompressedScreenshot;
}
1;
