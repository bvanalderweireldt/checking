#!/usr/bin/env perl
# Checking Perl
# DATABASE ACCESS AND QUERY CLASS
# Vanalderweireldt Benoit
# 01/08/2012

use DBI;
use strict;
package Db;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($INFO);

#CONSTRUCTOR
sub new {
	my ($class) = shift;
	
	my $target = "checkingweb";
	
	if( defined $_[0] && $_[0] == 1){
		$target .= "-test";
		INFO "### Test mode selected switch to the test db !";
	}
	
	my $self = {};	
	bless $self, $class;
		
	$self->{_dsn}		=	"DBI:mysql:database=$target;host=localhost;port=3306;mysql_socket=/var/lib/mysql/mysql.sock";
		
	$self->{_db} 		=	DBI->connect($self->{_dsn}, $target, "APdzfHI7xhXmDm139x1p3T") or die "Cannot connect to Mysql";
	
	return $self
}
#Load Email that have to be test,based on frequency
sub loadEmails {
	my $self = shift;
	#SQL Query load every emails
	my $load_all_emails_query = "select email, nom, prenom, cc, frequency from monitorServer_email";
	my $db_emails = $self->{_db}->prepare( $load_all_emails_query );
	$db_emails->execute() or die "Cannot load emails !";
	return $db_emails;
}
#LOAD ACTIVATE WEBSITES OF A GIVEN EMAIL ACCOUNT
sub loadWebsitesEmailAccount {
	my $self = shift;
	#SQL Query load all websites
	my $load_websites_query = "select id, label, keywords, status 
	from monitorServer_site as s right join monitorServer_email_has_sites as hs on s.id = hs.id_site where label != '' and monitor=1 
	and hs.email = ?";
	my $db_websites = $self->{_db}->prepare( $load_websites_query );
	$db_websites->execute( $_[0] ) or die "Cannot load websites !";
	return $db_websites;
}

#LOAD GLOBAL KEYWORDS
sub loadkeywords {
	my $self = shift;
	#SQL Query load all suspicious keywords 
	my $load_suspiciouskeywords_query = "select label from monitorServer_keywords";
	my $db_keywords = $self->{_db}->prepare( $load_suspiciouskeywords_query );
	$db_keywords->execute();
	my @keywords;
	while( my @keyword = $db_keywords->fetchrow_array ){
		push( @keywords, $keyword[0]) if ($keyword[0] ne "");
	}
	return @keywords;
}
#Query load the last recorded screenshot
sub loadscreenshot {
	my $self = shift;
	my $load_last_screenshot = "select screenshotResult from monitorServer_operation where id_site = ".$_[0]." order by dateStarted desc limit 0,1;";
	my ( $screenshot ) = $self->{_db}->selectrow_array( $load_last_screenshot );
	return $screenshot;
}
#INSERT ONE OPERATION IN DB
sub insert_operation {
	my $self = shift;
	my ($args) = $_[0];
	my $id = $_[0];
	my $screenshot = $_[1];
	my $ping = $_[2];
	my $cms = $_[3];
	my $generatingTime = $_[4];
	my $googleCode = $_[5];
	my $pageRank = $_[6];
	#SQL Query load all suspicious keywords 
	my $insert_operation = "INSERT INTO monitorServer_operation (id_ ,dateStarted ,screenshotResult ,pingResult ,matchKeywordResult, unMatchKeywordResult 
		,googleCodeResult ,versionCmsResult ,id_site, generatingTime, pageRank )
		VALUES (NULL , NOW() ,  ?,  ?, NULL, NULL , ? ,  ?,  ?, ?, ?);";
	my $db_keywords = $self->{_db}->prepare( $insert_operation );
	
	my $content_compress;
	use IO::Compress::Gzip qw(gzip $GzipError) ;
	
	gzip \$args->{content} => \$content_compress;
	
	INFO length($content_compress);
	INFO length($args->{content});
	
	$db_keywords->execute( $args->{content}, $args->{ping}, $args->{anaStatus}, $args->{cms}, $args->{id}, $args->{genTime}, $args->{pageRank});
}
#LOAD OPERATION FROM ID
sub loadOperationFromId {
	my $self = shift;
	my $id = $_[0];
	
}
1;
