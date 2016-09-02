#!/usr/bin/perl
#
## $Id: nodes_scratch.pl,v 1.1 2012/08/13 05:09:17 keiths Exp $
#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#
#  This file is part of Network Management Information System ("NMIS").
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


# Auto configure to the <nmis-base>/lib
use FindBin;
use lib "$FindBin::Bin/../lib";

# 
use strict;
use File::Basename;
use NMIS;
use func;
use Data::Dumper;
use NMIS::Integration;
use NMIS::Timing;

my $t = NMIS::Timing->new();

my $bn = basename($0);
my $usage = "Usage: $bn act=(which action to take)

\t$bn act=(run|monkey|banana)
\t$bn snmp=(true|false) - should the tool ensure that the SNMP service is included
\t$bn services=(true|false) - should the tool update services based on ServerRoles
\t$bn discover=(true|false) - should the tool update services based on ServerRoles

\t$bn simulate=(true|false)
\t$bn debug=(true|false)

e.g. $bn act=run

\n";

die $usage if (!@ARGV or ( @ARGV == 1 and $ARGV[0] =~ /^--?[h?]/));
my %arg = getArguements(@ARGV);

# load configuration table
my $C = loadConfTable(conf=>"",debug=>0);

my $act = $arg{act} ? $arg{act} : "";
my $discover = $arg{discover} ? getbool($arg{discover}) : 0;
my $debug = $arg{debug} ? $arg{debug} : 0;
my $simulate = $arg{simulate} ? getbool($arg{simulate}) : 0;
my $doSnmp = $arg{snmp} ? getbool($arg{snmp}) : 0;
my $doServices = $arg{services} ? getbool($arg{services}) : 0;
my $omkbin = $arg{omkbin} || "/usr/local/omk/bin";

# using $omkBin from NMIS::Integration
$omkBin = $omkbin;

my $removeServices = qr/(rsyslogd|SNMP_Service|SNMP_Daemon)/;

##### ACT=DISCOVER, this loads Services.nmis and then matches the program_name of each SNMP service against what is found in the service list


printSum("This script will load the NMIS Nodes file and validate the nodes being managed.");
printSum("  snmp update is set to $doSnmp (0 = disabled, 1 = enabled)");
printSum("  services update is set to $doServices (0 = disabled, 1 = enabled)");

my $cmdbCache = "";

my $xlsFile = "Node_Service_Report.xlsx";
my $xlsPath = "$C->{'<nmis_var>'}/$xlsFile";

my $nodesFile = "$C->{'<nmis_conf>'}/Nodes.nmis";

my %nodeIndex;
my @SUMMARY;

processNodes($nodesFile);
nodeServiceReport(xls_file_name => $xlsPath);

if ( defined $arg{email} and $arg{email} ne "" ) {
	my $from_address = $C->{mail_from_reports} || $C->{mail_from};

	emailSummary(subject => "Service Manager Results and Node Service Report Spreadsheet", C => $C, email => $arg{email}, summary => \@SUMMARY, from_address => $from_address, file_name => $xlsFile, file_path_name => $xlsPath);
}

exit 0;

sub processNodes {
	my $nodesFile = shift;
	my $LNT;
	
	my $omkNodes;
		
	if ( -r $nodesFile ) {
		$LNT = readFiletoHash(file=>$nodesFile);
		printSum("Loaded $nodesFile");
	}
	else {
		print "ERROR, could not find or read $nodesFile\n";
		exit 0;
	}
	
	# Load the old CSV first for upgrading to NMIS8 format
	# copy what we need
	my @addSnmpService;
	my @addRoleService;
	my @snmpBad;

	my @updates;
	my @nameCorrections;
	
	my $serviceIndex = getMonitoredServices();
	my $serverRoles = loadTable(dir=>'conf',name=>'ServerRoles');

	foreach my $node (sort keys %{$LNT}) {	
		my $S = Sys::->new; # get system object
		$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
		my $NI = $S->ndinfo;
		
		printSum($t->elapTime(). " Processing $node ServerRoles=$LNT->{$node}{ServerRoles} services=$LNT->{$node}{services} vendor=$NI->{system}{nodeVendor}") if $debug;
		
		# we will only process nodes when they are active.
		if ( $LNT->{$node}{active} eq "true" ) {
			my @newServices;
			
			# lets set SNMP max size to 2800!
			$LNT->{$node}{max_msg_size} = 2800;
			
			# looks for monitoring the SNMP daemon
			my $os = "";
			if ( $NI->{system}{nodeVendor} eq "Microsoft" ) {
				$os = "windows";
			}
			elsif ( $NI->{system}{nodeVendor} =~ /net-snmp|QNAP SYSTEMS|VMware/ ) {
				$os = "linux";
			}
			
			my @currentServices = split(",",$LNT->{$node}{services});
			my $serviceChanges = 0;
			
			my $snmpService = "snmp";

			#Are we monitoring the SNMP service?
			if ( $doSnmp ) {
				if ( $snmpService and not grep { $_ eq $snmpService } (@currentServices) ) {
					push(@newServices,$snmpService);
					push(@addSnmpService,$node);
					printSum("Add Service: $node $snmpService") if $debug;		
					$serviceChanges = 1;				
				}
			}

			# lets get the roles and make sure each service is there.
			if ( $doServices ) {
				my @roles = split(",",$LNT->{$node}{ServerRoles});
				
				#push the os onto the stack as a standard role, e.g. linux or windows.
				push(@roles,$os);
				
				foreach my $role (@roles) {
					#Are we monitoring the SNMP service?
					my @monitoredServices = split(",",$serverRoles->{$role}{monitoredServices});
					foreach my $service (@monitoredServices) {
						if ( $service and not grep { $_ eq $service } (@currentServices) ) {
							push(@newServices,$service);
							push(@addRoleService,$node) if not grep { $_ eq $node } (@addRoleService);
							printSum("Add Service: $node $service") if $debug;
							$serviceChanges = 1;		
						}
					}
					if ( $discover ) {
						my $regex = $serverRoles->{$role}{discoveryRegex};
						if ( exists $NI->{services} ) {
							#make a quicker index with just the name
							my $runningIndex;
							foreach my $runningService ( sort keys %{$NI->{services}} ) {
								my $hrSWRunName = $NI->{services}{$runningService}{hrSWRunName};
								my $hrSWRunParameters = $NI->{services}{$runningService}{hrSWRunParameters};
								# cast off the shackles of PID ownership
								$hrSWRunName =~ s/([\w\.]+)\:\d+/$1/;
								$runningIndex->{$hrSWRunName} = $NI->{services}{$runningService}{hrSWRunName};
								$runningIndex->{$hrSWRunParameters} = $NI->{services}{$runningService}{hrSWRunName};
							}
							
							foreach my $runningService ( sort keys %{$runningIndex} ) {
								if ( $runningService =~ /$regex/ ) {
									printSum("MATCHED: $node has hrSWRunName \"$runningService\" for role $role");
								}
							}
						}
						else {
							print "INFO: $node has no SNMP running services\n" if $debug;
						}						
					}
				}
			}


      #"httpd.exe:1092" : {
      #   "hrSWRunStatus" : "running",
      #   "hrSWRunType" : "application",
      #   "hrSWRunPerfMem" : "28348",
      #   "hrSWRunName" : "httpd.exe:1092",
      #   "hrSWRunPerfCPU" : "1235"
      #},  
			# lets get the roles and make sure each service is there.
			if ( $discover ) {
				# does the node have SNMP services list.
				if ( exists $NI->{services} ) {

					#make a quicker index with just the name
					my $runningIndex;
					foreach my $runningService ( sort keys %{$NI->{services}} ) {
						my $hrSWRunName = $NI->{services}{$runningService}{hrSWRunName};
						# cast off the shackles of PID ownership
						$hrSWRunName =~ s/([\w\.]+)\:\d+/$1/;
						$runningIndex->{$hrSWRunName} = $NI->{services}{$runningService}{hrSWRunName};
					}
					
					foreach my $runningService ( sort keys %{$runningIndex} ) {
						if ( exists $serviceIndex->{$runningService} ) {
							printSum("DISCOVERED: $node has hrSWRunName \"$runningService\" which is monitored service $serviceIndex->{$runningService}");
							last;
						}
					}
				}
				else {
					print "INFO: $node has no SNMP running services\n" if $debug;
				}
			}

			
			# make sure all the services we started with are still in there.
			foreach my $service (@currentServices) {
				if ( not grep { $_ eq $service } (@newServices) ) {
					if ( $service !~ /$removeServices/ ) {
						push(@newServices,$service);
					}
					else {
						printSum("Remove Service: $node $service") if $debug;		
					}
				}				
			}
			
			if ( $serviceChanges and @newServices ) {
				if ( $simulate eq "true" ) {
					printSum("SIMULATE: $node updating services with @newServices") if $debug;		
				}
				else {
					printSum("Services: $node updating services with @newServices") if $debug;		
					$LNT->{$node}{services} = join(",",@newServices);
				}
			}
		}
	}

	printSum("\n");

	printSum("Added SNMP Service to ". @addSnmpService . " nodes");
	my $addedservices = join("\n",@addSnmpService);
	printSum($addedservices);

	printSum("\n");

	printSum("Added Roles Service to ". @addRoleService . " nodes");
	my $addedservices = join("\n",@addRoleService);
	printSum($addedservices);

	printSum("\n");

	if ( not $simulate ) {
		my $backupFile = $nodesFile .".". time();
		my $backup = backupFile(file => $nodesFile, backup => $backupFile);
		if ( $backup ) {
			printSum("$nodesFile backup'ed up to $backupFile");
			writeHashtoFile(file => $nodesFile, data => $LNT);
			printSum("NMIS Nodes file $nodesFile saved");	
		}
		else {
			printSum("SKIPPING save: $nodesFile could not be backup'ed");
		}				
	}
}

sub printSum {
	my $message = shift;
	print "$message\n";
	push(@SUMMARY,$message);
}



#  'SNMP_Daemon' => {
#    'Name' => 'SNMP_Daemon',
#    'Poll_Interval' => '5m',
#    'Port' => '',
#    'Service_Name' => 'snmpd',
#    'Service_Type' => 'service'
#  },

sub getMonitoredServices {
	my $MS = loadTable(dir=>'conf',name=>'Services');
	my $serviceIndex;
	
	foreach my $monserv ( sort keys %$MS ) {
		if ( $MS->{$monserv}{Service_Type} eq "service" ) {
			my $name = $MS->{$monserv}{Service_Name};
			$serviceIndex->{$name} = $monserv;
		}	
	}
	return $serviceIndex;
}

#	my $desired = $args{desired} || $C->{'os_username'} || "nmis";





#sub makeReport {
#
#	end_xlsx(xls => $xls);
#}	
#
sub nodeServiceReport {
	my %args = @_;
	
	my $xls_file_name = $args{xls_file_name};

	my $xls;
	if ($xlsPath) {
		$xls = start_xlsx(file => $xlsPath);
	}

	# for group filtering
	my $group = $args{group} || "";
	
	# for exception filtering
	my $filter = $args{filter} || "";
	
	my $noExceptions = 1;
	my $LNT = loadLocalNodeTable();
	
	#print qq|"name","group","version","active","collect","last updated","icmp working","snmp working","nodeModel","nodeVendor","nodeType","roleType","netType","sysObjectID","sysObjectName","sysDescr","intCount","intCollect"\n|;
	my @headings = (
				"name",
				"group",
				"active",
				"serviceLevel",
				"ServerRoles",
				"services",
				"deviceType",
				"roleType",
				
				"nodeVendor",
				"nodeModel",
				"nodeType",
				
				"sysObjectID",
				"sysDescr",
			);

	my $sheet = add_worksheet(xls => $xls, title => "Node Admin Report", columns => \@headings);
	my $currow = 1;

	my $extra = " for $group" if $group ne "";
	my $cols = @headings;

	foreach my $node (sort keys %{$LNT}) {
		#if ( $LNT->{$node}{active} eq "true" ) {
		if ( 1 ) {
			if ( $group eq "" or $group eq $LNT->{$node}{group} ) {
				my $intCollect = 0;
				my $intCount = 0;
				my $S = Sys::->new; # get system object
				$S->init(name=>$node,snmp=>'false'); # load node info and Model if name exists
				my $NI = $S->ndinfo;
				my $IF = $S->ifinfo;
				my $exception = 0;
				my @issueList;

				# Is the node active and are we doing stats on it.
				if ( getbool($LNT->{$node}{active}) and getbool($LNT->{$node}{collect}) ) {
					for my $ifIndex (keys %{$IF}) {
						++$intCount;
						if ( $IF->{$ifIndex}{collect} eq "true") {
							++$intCollect;
						}
					}
				}
				my $sysDescr = $NI->{system}{sysDescr};
				$sysDescr =~ s/[\x0A\x0D]/\\n/g;
				$sysDescr =~ s/,/;/g;

				my $community = "OK";
				my $commClass = "info Plain";

				my $lastCollectPoll = defined $NI->{system}{lastCollectPoll} ? returnDateStamp($NI->{system}{lastCollectPoll}) : "N/A";
				my $lastCollectClass = "info Plain";

				my $lastUpdatePoll = defined $NI->{system}{lastUpdatePoll} ? returnDateStamp($NI->{system}{lastUpdatePoll}) : "N/A";
				my $lastUpdateClass = "info Plain";

				my $pingable = "unknown";
				my $pingClass = "info Plain";

				my $snmpable = "unknown";
				my $snmpClass = "info Plain";

				my $moduleClass = "info Plain";

				my $actClass = "info Plain Minor";
				if ( $LNT->{$node}{active} eq "false" ) {
					push(@issueList,"Node is not active");
				}
				else {
					$actClass = "info Plain";
					
					if ( $LNT->{$node}{active} eq "false" ) {
						$lastCollectPoll = "N/A";
					}	
					elsif ( not defined $NI->{system}{lastCollectPoll} or $LNT->{$node}{active} eq "false") {
						$lastCollectPoll = "unknown";
						$lastCollectClass = "info Plain Minor";
						$exception = 1;
						push(@issueList,"Last collect poll is unknown");
					}
					elsif ( $NI->{system}{lastCollectPoll} < (time - 60*15) ) {
						$lastCollectClass = "info Plain Major";
						$exception = 1;
						push(@issueList,"Last collect poll was over 5 minutes ago");
					}

					if ( $LNT->{$node}{active} eq "false" ) {
						$lastUpdatePoll = "N/A";
					}	
					elsif ( not defined $NI->{system}{lastUpdatePoll} ) {
						$lastUpdatePoll = "unknown";
						$lastUpdateClass = "info Plain Minor";
						$exception = 1;
						push(@issueList,"Last update poll is unknown");
					}
					elsif ( $NI->{system}{lastUpdatePoll} < (time - 86400) ) {
						$lastUpdateClass = "info Plain Major";
						$exception = 1;
						push(@issueList,"Last update poll was over 1 day ago");
					}

					$pingable = "true";
					$pingClass = "info Plain";
					if ( not defined $NI->{system}{nodedown} ) {
						$pingable = "unknown";
						$pingClass = "info Plain Minor";
						$exception = 1;
						push(@issueList,"Node state is unknown");
					}
					elsif ( $NI->{system}{nodedown} eq "true" ) {
						$pingable = "false";
						$pingClass = "info Plain Major";
						$exception = 1;
						push(@issueList,"Node is currently unreachable");
					}

					if ( $LNT->{$node}{collect} eq "false" ) {
						$snmpable = "N/A";
						$community = "N/A";
					}
					else {
						$snmpable = "true";

						if ( not defined $NI->{system}{snmpdown} ) {
							$snmpable = "unknown";
							$snmpClass = "info Plain Minor";
							$exception = 1;
							push(@issueList,"SNMP state is unknown");
						}
						elsif ( $NI->{system}{snmpdown} eq "true" ) {
							$snmpable = "false";
							$snmpClass = "info Plain Major";
							$exception = 1;
							push(@issueList,"SNMP access is currently down");
						}

						if ( $LNT->{$node}{community} eq "" ) {
							$community = "BLANK";
							$commClass = "info Plain Major";
							$exception = 1;
							push(@issueList,"SNMP Community is blank");
						}

						if ( $LNT->{$node}{community} eq "public" ) {
							$community = "DEFAULT";
							$commClass = "info Plain Minor";
							$exception = 1;
							push(@issueList,"SNMP Community is default (public)");
						}

						if ( $LNT->{$node}{model} ne "automatic"  ) {
							$moduleClass = "info Plain Minor";
							$exception = 1;
							push(@issueList,"Not using automatic model discovery");
						}

					}
				}

				my $wd = 850;
				my $ht = 700;

				my $idsafenode = $node;
				$idsafenode = (split(/\./,$idsafenode))[0];
				$idsafenode =~ s/[^a-zA-Z0-9_:\.-]//g;

				my $issues = join(":: ",@issueList);

				my $sysObject = "$NI->{system}{sysObjectName} $NI->{system}{sysObjectID}";
				my $intNums = "$intCollect/$intCount";

				$noExceptions = 0;
				my @columns;
				push(@columns,$LNT->{$node}{name});
				push(@columns,$LNT->{$node}{group});
				push(@columns,$LNT->{$node}{active});
				push(@columns,$LNT->{$node}{serviceLevel});
				push(@columns,$LNT->{$node}{ServerRoles});
				push(@columns,$LNT->{$node}{services});					
				push(@columns,$LNT->{$node}{deviceType});
				push(@columns,$NI->{system}{roleType});

				push(@columns,$NI->{system}{nodeVendor});
				push(@columns,"$NI->{system}{nodeModel} ($LNT->{$node}{model})");
				push(@columns,$NI->{system}{nodeType});
				
				push(@columns,$sysObject);
				push(@columns,$sysDescr);

				if ($sheet) {
					$sheet->write($currow, 0, [ @columns[0..$#columns] ]);
					++$currow;
				}
			}
		}
	}

	end_xlsx(xls => $xls);
	setFileProt($xlsPath);

}  # end sub nodeAdminSummary
