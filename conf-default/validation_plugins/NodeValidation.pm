# ****************************************************************************
#  Copyright Opmantek Limited (www.opmantek.com)
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

package NodeValidation;
our $VERSION = "2.0.1";

# what this validates:
#  ci - should be unique and present on each node
#  host - 

use Data::Dumper;

# validate_node, sub called by Node.pm to validate nodes, using plugins.
# Parameters:
# Node   - the Node object containing the new values to be validated
# Config - the system configuration object
# NMISNG - the NMISNG object to use
#returns 1 or 0 - node is valid or not and  list of errors
sub validate_node
{
    my (%args) = @_;
    my ($node, $C ,$NG) = @args{qw(node config nmisng)};
 
    my @errors = ();
    
    
    ## check if the ci already exists or not ?
    my $current_ci =  $node->configuration->{ci};
    my $current_host = $node->configuration->{host};
    my $current_host_bkp = $node->configuration->{host_backup};
    if ( my $error = validate_ci('ci_field' => $current_ci, node => $node,config => $C, nmisng=>$NG))
    {
        push @errors, $error;
    }
    elsif ( my $error = validate_host('current_host' => $current_host,node => $node,config => $C, nmisng=>$NG))
    {
        push @errors, $error;
    }
    elsif ( $error = validate_IP_addr('host' => $current_host,'host_backup' => $current_host_bkp, node => $node,config => $C, nmisng=>$NG))
    {
        push @errors, $error;
    }

    return (scalar(@errors), @errors);
}

# return error if ip/backup_ip exists in db , 
# return 0 if ip/backup_ip  does not exists in db.
sub validate_IP_addr
{
    my (%args) = @_;
    my ($node, $C ,$NG,$host,$host_backup) = @args{qw(node config nmisng host host_backup)};
    
    $NG->log->debug2(sub {"Validating IP address :- Checking if Primary and backup monitoring addresses are already associated or not ?"});


   
    ## check if its an update or insert ?
    my $model_data = $NG->get_nodes_model(      filter => {uuid => $node->uuid },
                                                fields_hash => {  
                                                                  'name' => 1, 
                                                                  'configuration.host' => 1,
                                                                  'configuration.host_backup' => 1
                                                        } );   
    
    if (my $error = $model_data->error)
    {
        $NG->log->error("Failed to get nodes model: $error");
        return ("Failed to get nodes model, Error validating IP field.");
    }
    
    my $node_configuration = $node->configuration;
    

    ## check if its a host name or ip or not.
      my ($ip, $bkp_ip);
        if ($host =~ /^\d+.\d+.\d+\.\d+$/ || $host_backup =~ /^\d+.\d+.\d+\.\d+$/ ){
            $ip = $host;
            $bkp_ip = $host_backup;
        }
        else{
            ## convert the host and backup host, to ip and backup ip address. 
            if ($node_configuration->{ip_protocol} eq 'IPv6')
            {
                $ip = NMISNG::Util::resolveDNStoAddrIPv6($host);
                $bkp_ip = NMISNG::Util::resolveDNStoAddrIPv6($host_backup);
            }
            else
            {
                $ip = NMISNG::Util::resolveDNStoAddr($host);
                $bkp_ip = NMISNG::Util::resolveDNStoAddr($host_backup);
            }
        }
    #
    
  
  

    my $data = $model_data->data();
    if (@{$data}){
        ## UPDATE
        ## if no changes in host on update
        if ($data->[0]->{configuration}->{host} eq $host && $data->[0]->{configuration}->{host_backup} eq $host_backup){
            $NG->log->debug2(sub {"No changes in host and backup host for the ".$node->name.", validation complete."}); 
            return 0;            
        }
        else{
            ## check if ip and backup if are part of some other db or not ?
            my ($error,$status) = db_ip_check(node=> $node,nmisng=> $NG,host => $host,host_backup => $host_backup);
            if ($status){
                ## all good host does not exist anywhere
                $NG->log->debug2(sub {"IP or Backup IP monitoring address does not exists in database, validation complete."}); 
                return 0;
            }
            else{
                
                $message = "IP:- $ip or Backup IP:- $bkp_ip monitoring address is already present in nodes:- ".$error;
                $NG->log->debug2(sub {$message}); 
                return ($message);
            }
        }
    }
    else{
        ## INSERT
        ## check if ip and backup if are part of some other db or not ?
            my ($error,$status) = db_ip_check(node=> $node,nmisng=> $NG,host => $host,host_backup => $host_backup);
            if ($status){
                ## all good host does not exist anywhere
                $NG->log->debug2(sub {"IP or Backup IP monitoring address does not exists in database, validation complete."}); 
                return 0;
            }
            else{
                $message = "IP:- $ip or Backup IP:- $bkp_ip monitoring address is already present in nodes:- ".$error;
                $NG->log->debug2(sub {$message}); 
                return ($message);
            }
    }
}   



## db check for ip.
# this checks if the ip/backup-ip , exists in db or not ?
sub db_ip_check
{
    my (%args) = @_;
    my ($node,$NG,$host,$host_backup) = @args{node,nmisng,host,host_backup};

    my $node_configuration = $node->configuration;
    
    ## convert the host and backup host, to ip and backup ip address. 
    my ($ip, $bkp_ip);
    
    
    if ($host =~ /^\d+.\d+.\d+\.\d+$/ || $host_backup =~ /^\d+.\d+.\d+\.\d+$/ ){
        $ip = $host;
        $bkp_ip = $host_backup;
    }
    else{
        if ($node_configuration->{ip_protocol} eq 'IPv6')
        {
            $ip = NMISNG::Util::resolveDNStoAddrIPv6($host);
            $bkp_ip = NMISNG::Util::resolveDNStoAddrIPv6($host_backup);
        }
        else
        {
            $ip = NMISNG::Util::resolveDNStoAddr($host);
            $bkp_ip = NMISNG::Util::resolveDNStoAddr($host_backup);
        }
    }

    ## query part for or and and.
    my $query = NMISNG::DB::get_query(
                                        and_part => {  concept => "catchall",
                                                        node_uuid => { '$ne' => $node->uuid } },
                                        
                                        or_part => {
                                            'data.host_addr' => $ip ,
                                            'data.host_addr_backup' => $bkp_ip,
                                            'data.host' => $ip,
                                            'data.host_backup' => $bkp_ip 
                                        }
                                    );

    ## required fields. 
    my $fields_hash = {        
                        'node_name'  => 1,
                        'node_uuid' => 1,
                        'concept'  => 1,
                        'data.host_addr' => 1,
                        'data.host_addr_backup' => 1,
                        'data.host' => 1,
                        'data.host_backup' => 1,
                    };


    ## db query to find data in inventory.
    my $entries = NMISNG::DB::find(
                    collection  => $NG->inventory_collection,
                    query       => $query,
                    fields_hash => $fields_hash                                  
                    );

    my @all;
    while ( my $entry = $entries->next )
    {
        push @all, $entry;
    }

    # if entries exist , then grab the node names and send it through.
    if (@all){
        foreach my $entry(@all){
            my $linked_data;
            if ($entry->{data}->{host_addr} || $entry->{data}->{host_addr_backup}){
                $linked_data = "$entry->{node_name} ($entry->{data}->{host_addr},$entry->{data}->{host_backup})";
            }
            else {
                $linked_data = "$entry->{node_name} ($entry->{data}->{host},$entry->{data}->{host_backup})";
            }
            push @names,$linked_data;
        }
        return(@names,0);
    }
    else{
         ## all good it does not exist anywhere else.
        return (undef,1);
    }

}




# return error if host exists in db , 
# return 0 if host  does not exists in db.
sub validate_host
{
    my (%args) = @_;
    my ($node, $C ,$NG,$host) = @args{qw(node config nmisng current_host)};
    
    $NG->log->debug2(sub {"Validating Host :- Checking if Hostname is already registered or not ?"});
      
    # look to see if any nodes exist with same ci value
    my ($nodes,$status) = db_check(nmisng=> $NG,filter_value => $host, filter_key => 'configuration.host' );
    if( $status == 0 ) {
        foreach $found_node (@$nodes) {
            # if there is a node and it has a different uuid then we have a conflict
            if( $found_node->{uuid} ne $node->uuid) {
                return ("Another node is already using host:$host, named:$found_node->{name}");
            }
        }
    }
    return 0;
}

## db check for host.
## this sub check if host exists in db or not ?
sub db_check
{
    my (%args) = @_;
    my ($NG,$filter_value,$filter_key) = @args{nmisng,filter_value,filter_key};

     ## check if the host is present in db for any node 
    my $model_data = $NG->get_nodes_model( filter => { $filter_key => $filter_value },
                                                fields_hash => {  
                                                                  'name' => 1, 
                                                                  'uuid' => 1,
                                                                  'configuration.ci' => 1
                                                        } );
    if (my $error = $model_data->error)
    {
        $NG->log->error("Failed to get nodes model: $error");
        return ("Failed to get nodes model, Error validating CI field.",0);
    }
    
    my $data = $model_data->data();
    my @nodes = ();
    if (@{$data}) {
        foreach my $entry(@{$data}){
            push @nodes,$entry;
        }
        return(\@nodes,0);
    }
    else{
        ## all good it does not exist anywhere else.
        return (\@nodes,1);
    }
}


# return error if custom field exists in db , 
# return 0 if custom field does not exists in db.
sub validate_ci
{
    my (%args) = @_;
    my ($node, $C ,$NG,$CIF) = @args{qw(node config nmisng ci_field)};
    
     $NG->log->debug2(sub {"Validating CI field :- Checking if CI already exists or not ?"});
    if( $CIF eq '' )
    {
        return "ci_field cannot be empty";
    }
    # look to see if any nodes exist with same ci value
    my ($nodes,$status) = db_check(nmisng=> $NG,filter_value => $CIF, filter_key => "configuration.ci" );
    if( $status == 0 ) {
        foreach $found_node (@$nodes) {
            # if there is a node and it has a different uuid then we have a conflict
            if( $found_node->{uuid} ne $node->uuid) {
                return ("Another node is already using ci:$CIF, named:$found_node->{name}");
            }
        }
    }
    return 0;
}
 
## dummy sub , which can be called by Node.pm for some other functionality .
sub create_valid
{
    my (%args) = @_;
    my ($node, $C ,$NG) = @args{qw(node config nmisng)};
    return (1, undef);
}
1;