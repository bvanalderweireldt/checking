#!/usr/bin/env perl
# Utils common fonction
# Vanalderweireldt Benoit
# 27/02/2013

package Utils{
use Time::HiRes qw(tv_interval gettimeofday);
#
#
# Initiate Logger
#
#
use Log::Log4perl;
my $LOGGER = Log::Log4perl->get_logger("Utils");

#
#
# Extract Arg value from command line if myarg=something this function will return 'something'
#
#
sub extractArgFromString{
	my ($args) = shift;
	
	#Is their any argument to return ?
	if( $args->{arg} =~ /^\D+=(\w+)/ ){
		return $1;
	}
	#No we logg it
	else{
		$LOGGER->error("Wrong argument passed, cannot extract the content");
		return 0;
	}
}
#
#
# Display Help
#
#
sub displayHelp{
	print "Checking Help :
	db={db+username} default=checkingweb
	gzip={0 or 1} gzip compression for screenshot default=1
	siteid={idsite} check only one site
	userid={userid} do a full scan for a given user
	debug={0 or 1} activate debug output default =1\n";
}
#
#
# Time freqency
#
#
my @timeData = localtime(time);
my $h = $timeData[2];
my $m = $timeData[1];
$frequency = 30;#Time frequency in min, it means websites who have frequency set to 2 will be check every hour, to 4 every 2 hours...
$t = int( $m / $frequency ) + ( $h * ( 60 / $frequency ) );
sub getFrequency{
	return $frequency;
}
sub getTimeSlot{
	return $t;
}
}
1
