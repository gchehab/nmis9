#!/bin/env perl
#
#  Copyright Opmantek Limited (www.opmantek.com)
#  
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#  
#  This file is part of Network Management Information System (NMIS).
#  
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).  
#  If not, see <http://www.gnu.org/licenses/>
#  
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com 
#  
#  User group details:
#  http://support.opmantek.com/users/
#  
# *****************************************************************************
#
# Trivial script to generate an event into syslog for testing purposes, usefull especially opEvents pipelines.

use strict;

my $debug = 0;

my $traplog = "/usr/local/nmis9/logs/trap.log";

#2023-09-24T22:17:01 omk-core1 SNMPv2-MIB::snmpTrapOID.0=BGP4-MIB::bgp.0.2 BGP4-MIB::bgpPeerRemoteAddr.192.168.128.188=192.168.128.188 BGP4-MIB::bgpPeerLastError.192.168.128.188="04 00 " BGP4-MIB::bgpPeerState.192.168.128.188=idle SNMP-COMMUNITY-MIB::snmpTrapAddress.0=10.117.21.30 SNMP-COMMUNITY-MIB::snmpTrapCommunity.0="ne14lunch!" SNMPv2-MIB::snmpTrapEnterprise.0=BGP4-MIB::bgp snmpTrapOID.0=BGP4-MIB::bgpTraps.0.2

trap_logit($traplog,"omk-core1	UDP: [10.117.45.5]:49919-&gt;[10.117.3.154]:162	SNMPv2-MIB::sysUpTime.0=62:18:49:42.81	SNMPv2-MIB::snmpTrapOID.0=BGP4-MIB::bgpTraps.0.2	BGP4-MIB::bgpPeerLastError.192.168.128.188=\"00 00 \"	BGP4-MIB::bgpPeerState.192.168.128.188=idle	SNMP-COMMUNITY-MIB::snmpTrapAddress.0=10.248.0.3	SNMP-COMMUNITY-MIB::snmpTrapCommunity.0=\"nothinghere\"	SNMPv2-MIB::snmpTrapEnterprise.0=BGP4-MIB::bgpTraps");

# this creates a CISCO! style syslog entry, DOES NOT WORK for normal syslog!
sub trap_logit {
	my $traplog = shift;
	my $trap = shift;

	my $time = returnTrapTime();
	my $out = "$time $trap";

 	print "$out\n" if $debug;

	if ( not $debug ) {
			open(OUT, ">>$traplog" ) or exception("$0: Couldn't open file $traplog for writing. $!","die");
			print OUT "$out\n";
			close(OUT) or exception("$0: Couldn't close file $traplog. $!","warn");
	}
}

sub returnTrapTime {
	my $time = shift;
	if ( ! defined $time ) { $time = time; }
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($time);
	#need to add 1 to month
	++$mon;
	#$year contains the number of years since 1900. To get the full year write:
	$year += 1900;
	if ($mon<10) {$mon = "0$mon";}
	if ($mday<10) {$mday = "0$mday";}
	if ($hour<10) {$hour = "0$hour";}
	if ($min<10) {$min = "0$min";}
	if ($sec<10) {$sec = "0$sec";}

	#Apr  6 12:41:35
	#2023-09-07T16:23:25
	return "$year-$mon-$mday". "T". "$hour:$min:$sec";
}
