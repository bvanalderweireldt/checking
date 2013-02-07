#!/usr/bin/env perl
# CGI Script to display screenshot by operation ID, the screen shot must be unmcompressed
# Vanalderweireldt Benoit
# 7/02/2013

BEGIN{
	use File::Basename;
	eval 'use lib "../'.dirname(__FILE__).'"';
	eval 'chdir "'.dirname(__FILE__).'"';
}

use Db;
use CGI;
use POSIX qw/strftime/;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

#Request handler
my $req = CGI->new;
#Error boolean of the script
my $error = 0;

#Content header of the answer
print "Content-type:text/html\r\n\r\n";
#check the request is correct POST method
print ( "Bad Request only POST is supported !\n" ) and $error=1 unless ( $req->request_method() eq "GET" );
#check the ID argument not empty
print ( "You need to provide an ID to get an operation screenshot !\n") and $error=1 unless ( $req->param('id') ne "" );

my $db = Db->new();

my $screenshot = $db->loadScreenShotByOperationId({ id => $req->param('id') });

my $uncompressedScreenshot;

gunzip \$screenshot => \$uncompressedScreenshot;

print $uncompressedScreenshot;


