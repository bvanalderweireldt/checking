#!/usr/bin/env perl
# CGI Script to display screenshot by operation ID, the screen shot must be unmcompressed
# Vanalderweireldt Benoit
# 7/02/2013

BEGIN{
	use File::Basename;
	eval 'chdir "'.dirname(__FILE__).'"';
	eval 'use lib "../"';
}

use Db;
use CGI;

#Request handler
my $req = CGI->new;
#Error boolean of the script
my $error = 0;

#Content header of the answer
print "Content-type:text/html\r\n\r\n";
#check the request is correct POST method
print ( "Bad Request only POST is supported !\n" ) and $error=1 unless ( $req->request_method() eq "GET" );
#check the ID argument not empty
print ( "You need to provide an ID to get an operation screenshot !\n") and die() unless ( $req->param('id') ne "" );

my $db = Db->new($req->param('test'));

my $content = $db->loadContentOperationId({ id => $req->param('id') });

if( $content =~ /^\d+$/ ){
	$content = $db->loadContentOperationId({ id => $content });
}

print $content;


