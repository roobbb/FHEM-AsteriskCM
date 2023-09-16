# $Id: 98_AsteriskCM.pm 1040 Version 1.0 2015-10-01 18:38:10Z marvin1978 $

package main;

use strict;
use warnings;
use DevIo;
use MIME::Base64;

sub AsteriskCM_Initialize($) {
  my ($hash) = @_;

  $hash->{SetFn}     = "AsteriskCM_Set";
  $hash->{GetFn}     = "AsteriskCM_Get";
  $hash->{DefFn}     = "AsteriskCM_Define";
  $hash->{NotifyFn}  = "AsteriskCM_Notify";
  $hash->{UndefFn}   = "AsteriskCM_Undefine";
	$hash->{AttrFn}    = "AsteriskCM_Attr";
	$hash->{ReadFn}    = "AsteriskCM_Read";
	$hash->{ReadyFn}   = "AsteriskCM_Ready";
	$hash->{NOTIFYDEV} = "global";
	
  $hash->{AttrList} = "disable:1,0 ".
											"do_not_notify:1,0 ".
											"contextIncoming ".
											"contextOutgoing ".
											"local-area-code ".
                      "country-code ".
                      "remove-leading-zero:0,1 ".
                      "reverse-search-cache-file ".
                      "reverse-search:sortable-strict,textfile,klicktel.de,dasoertliche.de,search.ch,dasschnelle.at ".
                      "reverse-search-cache:0,1 ".
                      "reverse-search-text-file ".
											$readingFnAttributes;
	
	return undef;
}

sub AsteriskCM_Define($$) {
  my ($hash, $def) = @_;
	my $now = time();
	my $name = $hash->{NAME}; 
	
	my @a = split( "[ \t][ \t]*", $def );
	
	if ( int(@a) < 3 ) {
    my $msg =
"Wrong syntax: define <name> AsteriskCM <server> [<user> <port>]";
    Log3 $name, 4, $msg;
    return $msg;
  }
	
	$hash->{SERVER} = $a[2];
	$hash->{USER} = $a[3] ? $a[3] : "admin";
	$hash->{PORT} = $a[4] ? $a[4] : 5038;
	
	my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
	my ($err, $password) = getKeyValue($index);
	
	$hash->{helper}{PWD_NEEDED}=1 if ($err || !$password);
	
	readingsSingleUpdate($hash,"state","active",1);

	RemoveInternalTimer($hash);
	
	
	if ($init_done) {
		AsteriskCM_Disconnect($hash);
		InternalTimer(gettimeofday()+2, "AsteriskCM_Connect", $hash, 0) if( AttrVal($name, "disable", 0 ) != 1 );
	
		AsteriskCM_loadTextFile($hash) if(defined(AttrVal($name, "reverse-search-text-file" , undef)) && AttrVal($name, "disable", 0 ) != 1);
		
	}
	
	delete $hash->{helper}{Call_};
	
	return undef;
}

sub AsteriskCM_Undefine($$) {
  my ($hash, $arg) = @_;
	
  AsteriskCM_Disconnect($hash);
	
  RemoveInternalTimer($hash);
	
  return undef;
}


sub AsteriskCM_Set($@) {
	my ($hash, $name, $cmd, @args) = @_;
	
	my @sets = ();
	
	push @sets, "password" if($hash->{helper}{PWD_NEEDED});
	push @sets, "newPassword" if(!$hash->{helper}{PWD_NEEDED});
	push @sets, "reconnect" if(!$hash->{helper}{PWD_NEEDED});
	push @sets, "rereadCache" if(defined(AttrVal($name, "reverse-search-cache-file" , undef)));
  push @sets, "rereadTextfile" if(defined(AttrVal($name, "reverse-search-text-file" , undef)));
	
	return join(" ", @sets) if ($cmd eq "?");
	
	return "$name is disabled. Enable it to use set AsteriskCM [...]" if( AttrVal($name, "disable", 0 ) == 1 );
	
	my $usage = "Unknown argument ".$cmd.", choose one of ".join(" ", @sets) if(scalar @sets > 0);
	
	if ($cmd eq "password") {
		return AsteriskCM_setPwd ($hash,$name,@args) if($hash->{helper}{PWD_NEEDED});
    Log3 $name, 2, "$name - SOMEONE UNWANTED TRIED TO SET NEW PASSWORDs!!!";
    return "I didn't ask for a password, so go away!!!";
	}
	elsif ($cmd eq "newPassword" ){
		unshift @args, "newPassword";
		return AsteriskCM_setPwd ($hash,$name,@args) if(!$hash->{helper}{PWD_NEEDED});
	}
	elsif ($cmd eq "reconnect" ){
		AsteriskCM_reConnect($hash);
		return;
	}
	elsif($cmd eq "rereadCache") {
    AsteriskCM_loadCacheFile($hash);
    return undef;
  }
  elsif($cmd eq "rereadTextfile") {
    AsteriskCM_loadTextFile($hash);
    return undef;
  }
	else {
		return $usage;
	}
}

#####################################
# Get function for returning a reverse search name
sub AsteriskCM_Get($@) {
	my ($hash, @arguments) = @_;
	
	return "argument missing" if(int(@arguments) < 2);

  if($arguments[1] eq "search" and int(@arguments) >= 3) {
    return AsteriskCM_reverseSearch($hash, AsteriskCM_normalizePhoneNumber($hash, join '', @arguments[2..$#arguments]));
  }
	elsif($arguments[1] eq "showCacheEntries" and exists($hash->{helper}{CACHE})) {
    my $table = "";
       
    my $number_width = 0;
    my $name_width = 0;
        
    foreach my $number (keys %{$hash->{helper}{CACHE}}) {
      $number_width = length($number) if($number_width < length($number));
      $name_width = length($hash->{helper}{CACHE}{$number}) if($name_width < length($hash->{helper}{CACHE}{$number}));
    }
    my $head = sprintf("%-".$number_width."s   %s" ,"Number", "Name"); 
    foreach my $number (sort { lc($hash->{helper}{CACHE}{$a}) cmp lc($hash->{helper}{CACHE}{$b}) } keys %{$hash->{helper}{CACHE}}) {
			my $string = sprintf("%-".$number_width."s - %s" , $number,$hash->{helper}{CACHE}{$number}); 
      $table .= $string."\n";
    }
        
    return $head."\n".("-" x ($number_width + $name_width + 3))."\n".$table;
  }
  elsif($arguments[1] eq "showTextfileEntries" and exists($hash->{helper}{TEXTFILE})) {
    my $table = "";
       
    my $number_width = 0;
    my $name_width = 0;
        
    foreach my $number (keys %{$hash->{helper}{TEXTFILE}}) {
      $number_width = length($number) if($number_width < length($number));
      $name_width = length($hash->{helper}{TEXTFILE}{$number}) if($name_width < length($hash->{helper}{TEXTFILE}{$number}));
    }
    my $head = sprintf("%-".$number_width."s   %s" ,"Number", "Name"); 
    foreach my $number (sort { lc($hash->{helper}{TEXTFILE}{$a}) cmp lc($hash->{helper}{TEXTFILE}{$b}) } keys %{$hash->{helper}{TEXTFILE}}) {
      my $string = sprintf("%-".$number_width."s - %s" , $number,$hash->{helper}{TEXTFILE}{$number}); 
      $table .= $string."\n";
    }
        
    return $head."\n".("-" x ($number_width + $name_width + 3))."\n".$table;
  }
  else {
    return "unknown argument ".$arguments[1].", choose one of search".(exists($hash->{helper}{CACHE}) ? " showCacheEntries" : "").(exists($hash->{helper}{TEXTFILE}) ? " showTextfileEntries" : ""); 
  }
}


sub AsteriskCM_Attr($@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
	
  my $orig = $attrVal;
	
	my $hash = $defs{$name};
	
	if ( $attrName eq "disable" ) {

		if ( $cmd eq "set" && $attrVal == 1 ) {
			if ($hash->{READINGS}{state}{VAL} eq "connected") {
				RemoveInternalTimer($hash);
				AsteriskCM_Disconnect($hash);
			}
		}
		elsif ( $cmd eq "del" || $attrVal == 0 ) {
			if ($hash->{READINGS}{state}{VAL} ne "connected") {
				InternalTimer(gettimeofday()+1, "AsteriskCM_Connect", $hash, 0);
			}
		}
	}
	else {
	
		if ($cmd eq "set") {
			if($attrName eq "reverse-search-cache-file") {
				return AsteriskCM_loadCacheFile($hash, $attrVal);
			}
					
			if($attrName eq "reverse-search-text-file") {
				return AsteriskCM_loadTextFile($hash, $attrVal);
			}
		}
		
		if ($cmd eq "del") {
			if($attrName eq "reverse-search-cache") {
				delete($hash->{helper}{CACHE}) if(defined($hash->{helper}{CACHE}));
			} 
					
			if($attrName eq "reverse-search-text-file") {
				 delete($hash->{helper}{TEXTFILE}) if(defined($hash->{helper}{TEXTFILE}));
			}
		}
		
	}
	
	return;
}

sub AsteriskCM_Notify($$) {
    my ($hash,$dev) = @_;
		
		my $name = $hash->{NAME}; 

    return if($dev->{NAME} ne "global");
    return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
		
		$hash->{CONNECTS}=0;
		
		AsteriskCM_Disconnect($hash);
		InternalTimer(gettimeofday()+2, "AsteriskCM_Connect", $hash, 0) if( AttrVal($name, "disable", 0 ) != 1 );
		
    AsteriskCM_loadTextFile($hash) if(defined(AttrVal($name, "reverse-search-text-file" , undef)));
		
		return undef;
}

#####################################
# Connects to the AMI Server
sub AsteriskCM_Connect($) {
	my ($hash) = @_;
	my $name = $hash->{NAME}; 
		
	my $ret;
	
	DevIo_CloseDev($hash);
	
	if( AttrVal($name, "disable", 0 ) != 1 ) {
		
		$hash->{DeviceName} = $hash->{SERVER}.":".$hash->{PORT};
		
		$ret=DevIo_OpenDev($hash, 0, "AsteriskCM_Login");	
					
		Log3 $name, 4, "AsteriskCM ($name): connected to $hash->{SERVER}:$hash->{PORT}";	
				
	}
	else {
		Log3 $name, 4, "AsteriskCM ($name): Device is disabled. Could not connect.";
	}
	
	return $ret;
}


#####################################
# Disconnects from AMI 
sub AsteriskCM_Disconnect($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
	
	AsteriskCM_Logoff($hash);
	
	RemoveInternalTimer($hash);
	
	readingsSingleUpdate($hash, "state", "disconnected", 1);
	  
	DevIo_CloseDev($hash);	
	
	$hash->{CONNECTIONSTATE} = "disconnected";
	$hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
	
	Log3 $name, 3, "AsteriskCM ($name): Disonnected.";
	
	return undef;
}

sub AsteriskCM_reConnect($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "AsteriskCM ($name): reconnect";

  AsteriskCM_Disconnect($hash);
  InternalTimer(gettimeofday()+1, "AsteriskCM_Connect", $hash, 0) if( AttrVal($name, "disable", 0 ) != 1 );
}

#####################################
# Sends Login to AMI
sub AsteriskCM_Login ($) {
	my ($hash) = @_;
	my $name = $hash->{NAME}; 
	
	my $pwd="";
	
	$hash->{CONNECTS}++;
	$hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
	
	$hash->{CONNECTIONSTATE} = "connected";
	
	my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
	my $key = getUniqueId().$index;
	
	my ($err, $password) = getKeyValue($index);
        
	if ($err) {
		$hash->{helper}{PWD_NEEDED} = 1;
		Log3 $name, 4, "AsteriskCM ($name): unable to read password from file: $err";
		return undef;
	}	  
	
	if ($password) {
		$pwd=decode_base64($password);
	}
	
	return undef if ($pwd eq "");
	
	DevIo_SimpleWrite($hash,"Action: Login\r\n",0);
	DevIo_SimpleWrite($hash,"Username: ".$hash->{USER}."\r\n",0);
	DevIo_SimpleWrite($hash,"Secret: ".$pwd."\r\n",0);
	DevIo_SimpleWrite($hash,"Events: call\r\n",0);
	DevIo_SimpleWrite($hash,"\r\n",0);
	
	return undef;
}

#####################################
# Sends Logoff to AMI
sub AsteriskCM_Logoff ($) {
	my ($hash) = @_;
	my $name = $hash->{NAME}; 
	
	
	DevIo_SimpleWrite($hash,"Action: Logoff\r\n",0);
	DevIo_SimpleWrite($hash,"\r\n",0);
	
	return undef;
}




#####################################
# Reconnects to Asterisk Manager Interface in case of disconnects
sub AsteriskCM_Ready($)
{
    my ($hash) = @_;
		
		if ($hash->{CONNECTIONSTATE} eq "connected") {
			$hash->{CONNECTIONSTATE} = "disconnected";
			$hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
		
			readingsSingleUpdate($hash, "state", "disconnected", 1);
		}
		
    return DevIo_OpenDev($hash, 1, "AsteriskCM_Login");
}

#####################################
# Handles the login and calls
sub AsteriskCM_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
	my $tHash;
	
	if ( AttrVal($name, "disable", 0 ) != 1 ) {
	
		my $buf = DevIo_SimpleRead($hash);
		
		return "" if(!defined($buf));
  
		my @temp = split(/\bEvent\b: /,$buf);
		
				
		foreach (@temp) {
			
			next if ($_ eq "");
			
			my $buffer = "Event: ".$_;
			chomp $buffer;
		
			$hash->{BUFFER} = $buffer;
			
			Log3 $name,5,$buffer;
		
			my $i=0;
			foreach my $data (split( /^/m, $buffer)) {
				$i++;
				
				chomp $data;
				chop $data;
				
				my @a = split(": ",$data);
				
				$tHash->{$a[0]}=$a[1] if ($a[0] && $a[1]);
			}
			
			my $context;
			
			if ($tHash->{Message} && $tHash->{Message} eq "Authentication failed") {
				Log3 $name, 2, "AsteriskCM ($name): could not login to AMI. $tHash->{Message}. Retry in 20 seconds.";
				AsteriskCM_Disconnect( $hash );
				InternalTimer(gettimeofday()+20, "AsteriskCM_Connect", $hash, 0);			
			}
			
			if ($tHash->{Message} && $tHash->{Message} eq "Authentication accepted") {
				Log3 $name, 4, "AsteriskCM ($name): Login: $tHash->{Message}.";
				readingsSingleUpdate($hash,"state","connected",1);
			}
			
			if ($tHash->{Event} && $tHash->{Event} eq "Newchannel" && $tHash->{Context} && $tHash->{Context} eq AttrVal($name,"contextOutgoing","-") && $tHash->{Exten} && $tHash->{Exten} ne "") {
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{context} = "outgoing";
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{UniqueID} = $tHash->{Uniqueid};
			}
			
			if ($tHash->{Event} && $tHash->{Event} eq "Newchannel" && $tHash->{Context} && $tHash->{Context} eq AttrVal($name,"contextIncoming","-") && $tHash->{Exten} && $tHash->{Exten} ne "") {
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{context} = "incoming";
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{UniqueID} = $tHash->{Uniqueid};
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_number}=$tHash->{Exten};
			}
						
			if ($tHash->{Event} && $tHash->{Event} eq "DialBegin" && $hash->{helper}{"Call_".$tHash->{Uniqueid}} && $hash->{helper}{"Call_".$tHash->{Uniqueid}}{context} eq "outgoing") {
			
				Log3 $name, 4, "AsteriskCM ($name): outgoing call.";

				my @external_number = split("@",$tHash->{Dialstring});

				my $internal_connection_temp = $tHash->{Channel};
				$internal_connection_temp =~ /SIP\/(\d+)\-(\d+)/;
				my $internal_connection = $1;
				
				my $extern_num=AsteriskCM_externalNumber ($hash,$external_number[0]);
				
				my $external_name="-";
				
				$external_name=AsteriskCM_reverseSearch($hash,$extern_num) if(AttrVal($name, "reverse-search", "none") ne "none");
				
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_connection}=$tHash->{Destination};
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_number}=$tHash->{CallerIDNum};
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_number}=$extern_num;
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_name}=$external_name;
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_connection}=$internal_connection;
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{state}="ringing";
				
				readingsBeginUpdate($hash);
				
				readingsBulkUpdate($hash,"event","call");
				readingsBulkUpdate($hash,"direction","outgoing");
				readingsBulkUpdate($hash,"call_id",$tHash->{Uniqueid});
				readingsBulkUpdate($hash,"external_connection",$tHash->{Destination});
				readingsBulkUpdate($hash,"internal_number",$tHash->{CallerIDNum});
				readingsBulkUpdate($hash,"external_number",$extern_num);
				readingsBulkUpdate($hash,"external_name",$external_name);
				readingsBulkUpdate($hash,"internal_connection",$internal_connection);
				
				readingsEndUpdate($hash, 1);
			}
			
                        if ($tHash->{Event} && $tHash->{Event} eq "DialBegin" && $hash->{helper}{"Call_".$tHash->{Uniqueid}} && $hash->{helper}{"Call_".$tHash->{Uniqueid}}{context} eq "incoming") {
				
				Log3 $name, 4, "AsteriskCM ($name): incoming call.";
				
				my $extern_num=AsteriskCM_externalNumber ($hash,$tHash->{CallerIDNum});
				
				my $external_name = "-";
				
				$external_name=AsteriskCM_reverseSearch($hash,$extern_num) if(AttrVal($name, "reverse-search", "none") ne "none");
				
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_connection}=$tHash->{Channel};
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_number}=$extern_num;
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_name}=$external_name;
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_connection}=$tHash->{Dialstring};
				$hash->{helper}{"Call_".$tHash->{Uniqueid}}{state}="ringing";
				
				readingsBeginUpdate($hash);
				
				readingsBulkUpdate($hash,"event","call");
				readingsBulkUpdate($hash,"direction","incoming");
				readingsBulkUpdate($hash,"call_id",$tHash->{Uniqueid});
				readingsBulkUpdate($hash,"external_connection",$tHash->{Channel});
				readingsBulkUpdate($hash,"internal_number",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_number});
				readingsBulkUpdate($hash,"external_number",$extern_num);
				readingsBulkUpdate($hash,"internal_connection",$tHash->{Dialstring});
				readingsBulkUpdate($hash,"external_name",$external_name);
				
				readingsEndUpdate($hash, 1);
			}
			
			if ($tHash->{Event} eq "BridgeEnter" && $hash->{helper}{"Call_".$tHash->{Uniqueid}}) {
			
				Log3 $name, 4, "AsteriskCM ($name): call connected.";
				
				if ($hash->{helper}{"Call_".$tHash->{Uniqueid}}{state} && $hash->{helper}{"Call_".$tHash->{Uniqueid}}{state} eq "ringing") {
					my $running_calls=ReadingsVal($name,"running_calls",0);
					$running_calls++;
				
				
					$hash->{helper}{"Call_".$tHash->{Uniqueid}}{state}="connected";
					$hash->{helper}{"Call_".$tHash->{Uniqueid}}{conn_time}=gettimeofday();
				
					readingsBeginUpdate($hash);
					
					readingsBulkUpdate($hash,"event","connect");
					readingsBulkUpdate($hash,"direction",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{context});
					readingsBulkUpdate($hash,"external_connection",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_connection});
					readingsBulkUpdate($hash,"internal_number",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_number});
					readingsBulkUpdate($hash,"external_number",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_number});
					readingsBulkUpdate($hash,"call_id",$tHash->{Uniqueid});
					readingsBulkUpdate($hash,"internal_connection",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_connection});
					readingsBulkUpdate($hash,"external_name",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_name});
					readingsBulkUpdate($hash,"running_calls",$running_calls);
					
					readingsEndUpdate($hash, 1);
				}
			}
			
			if ($tHash->{Event} eq "Hangup" && $hash->{helper}{"Call_".$tHash->{Uniqueid}}) {
			
				Log3 $name, 4, "AsteriskCM ($name): Hangup.";
				
				my $call_duration=0;
				$call_duration=gettimeofday()-$hash->{helper}{"Call_".$tHash->{Uniqueid}}{conn_time} if ($hash->{helper}{"Call_".$tHash->{Uniqueid}}{conn_time});
				
				my $running_calls=ReadingsVal($name,"running_calls",0);
				$running_calls-- if ($hash->{helper}{"Call_".$tHash->{Uniqueid}}{state} eq "connected");
				$running_calls = 0 if ($running_calls < 0);
				
				readingsBeginUpdate($hash);
				
				readingsBulkUpdate($hash,"event","disconnect");
				readingsBulkUpdate($hash,"direction",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{context});
				readingsBulkUpdate($hash,"call_duration",round($call_duration,0));
				readingsBulkUpdate($hash,"external_connection",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_connection});
				readingsBulkUpdate($hash,"internal_number",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_number});
				readingsBulkUpdate($hash,"external_number",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_number});
				readingsBulkUpdate($hash,"call_id",$tHash->{Uniqueid});
				readingsBulkUpdate($hash,"internal_connection",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_connection});
				readingsBulkUpdate($hash,"external_name",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_name});
				readingsBulkUpdate($hash,"running_calls",$running_calls);
				
				if ($call_duration <= 0 && $hash->{helper}{"Call_".$tHash->{Uniqueid}}{context} && $hash->{helper}{"Call_".$tHash->{Uniqueid}}{context} eq "incoming") {
					readingsBulkUpdate($hash,"missed_call",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_number});
					readingsBulkUpdate($hash,"missed_call_name",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{external_name});
					readingsBulkUpdate($hash,"missed_call_line",$hash->{helper}{"Call_".$tHash->{Uniqueid}}{internal_number});
				}
				
				readingsEndUpdate($hash, 1);
				
				delete $hash->{helper}{"Call_".$tHash->{Uniqueid}};
				delete $hash->{helper}{Call_};
			}
			
			Log3 $name, 5, "AsteriskCM ($name): ".$buffer."\n___________________________________________________________";
		}
		
		
		
		delete ($hash->{BUFFER});
		$buf="" if ($buf);
	}
	return undef;
}

#####################################
# sets AMI password
sub AsteriskCM_setPwd($$@) {
	my ($hash, $name, @pwd) = @_;
	 
	return "Password can't be empty" if (!@pwd);
	
	if ($pwd[0] eq "newPassword") {
		shift(@pwd);
		if (AsteriskCM_checkPwd ($hash,$pwd[0]) && $pwd[1]) {
			shift(@pwd);
		}
		else {
			Log3 $name, 2, "AsteriskCM ($name). Someone tried to set a new password.";
			return "Old password is wrong" if ($pwd[1]);
			return "New password is mandatory" if (!$pwd[1]);
		}
	}
	
	my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
  my $key = getUniqueId().$index;
	
	
	my $pwdString=join(':', @pwd);
	
	$pwdString=encode_base64($pwdString);
	$pwdString =~ s/^\s+|\s+$//g;
		 
	my $err = setKeyValue($index, $pwdString);
  
	return "error while saving the password - $err" if(defined($err));
  
	delete($hash->{helper}{PWD_NEEDED}) if(exists($hash->{helper}{PWD_NEEDED}));
	
	AsteriskCM_reConnect($hash);
	
	Log3 $name, 4, "AsteriskCM ($name). New Password set.";
	
	return "password successfully saved";
	 
}

#####################################
# reads the password and checks it
sub AsteriskCM_checkPwd ($$) {
	my ($hash, $pwd) = @_;
	my $name = $hash->{NAME};
    
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
  my $key = getUniqueId().$index;
	
	my ($err, $password) = getKeyValue($index);
        
  if ($err) {
		$hash->{helper}{PWD_NEEDED} = 1;
    Log3 $name, 4, "AsteriskCM ($name): unable to read password from file: $err";
    return undef;
  }  
	
	if ($password) {
		my @pwds=split(":",decode_base64($password));
				
		return "no password saved" if (!@pwds);
		
		foreach my $pw (@pwds) {
			return 1 if ($pw eq $pwd);
		}
	}
	
	return 0;
}

#####################################
# processes an external phone number
sub AsteriskCM_externalNumber ($$) {
	my ($hash,$external_number) = @_;
	 
	my $name = $hash->{NAME};
	my $area_code = AttrVal($name, "local-area-code", "");
  my $country_code = AttrVal($name, "country-code", "0049");
	
	$external_number =~ s/^0// if(AttrVal($name, "remove-leading-zero", "0") eq "1");

	$external_number =~ s/^\+49/0/;
	$external_number =~ s/^\+[1-9]{2}/00/;
	
	# Remove Call-By-Call number (Germany)
  $external_number =~ s/^(010\d\d|0100\d\d)//g if($country_code eq "0049");
     
	# Remove Call-By-Call number (Austria)
	$external_number =~ s/^10\d\d//g if($country_code eq "0043");
                
  # Remove Call-By-Call number (Swiss)
  $external_number =~ s/^(107\d\d|108\d\d)//g if($country_code eq "0041");
            
  if (not $external_number =~ /^0/ && $area_code ne "") {
    if ($area_code =~ /^0[1-9]\d+$/) {
      $external_number = $area_code.$external_number;
    }
    else {
      Log3 $name, 2, "AsteriskCM ($name): given local area code '$area_code' is not an area code. therefore will be ignored";
    }
  }

  # Remove trailing hash sign and everything afterwards
  $external_number =~ s/#.*$//;
	
	return $external_number;
}

#####################################
# performs a reverse search 
sub AsteriskCM_reverseSearch ($$) {
	my ($hash,$number) = @_;
	
	my $name = $hash->{NAME};
  my $result;
  my $status;
  my $invert_match = undef;
  my @attr_list = split("(,|\\|)", AttrVal($name, "reverse-search", ""));
	
	foreach my $method (@attr_list) {
		if($method eq "textfile")
        {
            if(exists($hash->{helper}{TEXTFILE}) and defined($hash->{helper}{TEXTFILE}{$number}))
            {
                Log3 $name, 4, "AsteriskCM ($name): using textfile for reverse search of $number";
                return $hash->{helper}{TEXTFILE}{$number};
            }
        }
    elsif($method =~ /^(klicktel.de|dasoertliche.de|dasschnelle.at|search.ch)$/)
        {      
            # Using Cache if enabled
            if(AttrVal($name, "reverse-search-cache", "0") eq "1" and defined($hash->{helper}{CACHE}{$number}))
            {
                Log3 $name, 4, "AsteriskCM ($name): using cache for reverse search of $number";
                if($hash->{helper}{CACHE}{$number} ne "timeout" or $hash->{helper}{CACHE}{$number} ne "unknown")
                {
                    return $hash->{helper}{CACHE}{$number};
                }
            }    
            
        
            # Ask klicktel.de
            if($method eq "klicktel.de")
            { 
                Log3 $name, 4, "AsteriskCM ($name): using klicktel.de for reverse search of $number";

                $result = GetFileFromURL("http://openapi.klicktel.de/searchapi/invers?key=cfcd305f3c609b850c015d14f3ce150e&number=".$number, 5, undef, 1);
                if(not defined($result))
                {
                    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
                    {
                        $status = "timeout";
                        undef($result);
                    }
                }
                else
                {
                    if($result =~ /"displayname":"([^"]*?)"/)
                    {
                        $invert_match = $1;
                        $invert_match = AsteriskCM_html2txt($invert_match);
                        AsteriskCM_writeToCache($hash, $number, $invert_match);
                        undef($result);
                        return $invert_match;
                    }
                    
                    $status = "unknown";
                }
            }

            # Ask dasoertliche.de
            elsif($method eq "dasoertliche.de")
            {
                Log3 $name, 4, "AsteriskCM ($name): using dasoertliche.de for reverse search of $number";

                $result = GetFileFromURL("http://www1.dasoertliche.de/?form_name=search_inv&ph=".$number, 5, undef, 1);
                if(not defined($result))
                {
                    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
                    {
                        $status = "timeout";
                        undef($result);
                    }
                }
                else
                {
                    #Log 2, $result;
                    if($result =~ /<a href="http\:\/\/.+?\.dasoertliche\.de.+?".+?class="name ".+?><span class="">(.+?)<\/span>/)
                    {
                        $invert_match = $1;
                        $invert_match = AsteriskCM_html2txt($invert_match);
                        AsteriskCM_writeToCache($hash, $number, $invert_match);
                        undef($result);
                        return $invert_match;
                    }
                    elsif(not $result =~ /wir konnten keine Treffer finden/)
                    {
                        Log3 $name, 3, "AsteriskCM ($name): the reverse search result for $number could not be extracted from dasoertliche.de. Please contact the FHEM community.";
                    }
                    
                    $status = "unknown";
                }
            }
        

            # SWITZERLAND ONLY!!! Ask search.ch
            elsif($method eq  "search.ch")
            {
                Log3 $name, 4, "AsteriskCM ($name): using search.ch for reverse search of $number";

                $result = GetFileFromURL("http://tel.search.ch/api/?key=18ce24db45f849efcb61cf172a5c74d6&maxnum=1&was=".$number, 5, undef, 1);
                if(not defined($result))
                {
                    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
                    {
                        $status = "timeout";
                        undef($result);
                    }
                }
                else
                {
                    #Log 2, $result;
                    if($result =~ /<entry>(.+?)<\/entry>/s)
                    {
                        my $xml = $1;
                        
                        $invert_match = "";
                        
                        if($xml =~ /<tel:firstname>(.+?)<\/tel:firstname>/)
                        {
                            $invert_match .= $1;
                        }
                        
                        if($xml =~ /<tel:name>(.+?)<\/tel:name>/)
                        {
                            $invert_match .= " $1";
                        }
                        
                        if($xml =~ /<tel:occupation>(.+?)<\/tel:occupation>/)
                        {
                            $invert_match .= ", $1";
                        }
                        
                        $invert_match = AsteriskCM_html2txt($invert_match);
                        AsteriskCM_writeToCache($hash, $number, $invert_match);
                        undef($result);
                        return $invert_match;
                    }
                    
                    $status = "unknown";
                }
            }

            # Austria ONLY!!! Ask dasschnelle.at
            elsif($method eq "dasschnelle.at")
            {
                Log3 $name, 4, "AsteriskCM ($name): using dasschnelle.at for reverse search of $number";

                $result = GetFileFromURL("http://www.dasschnelle.at/result/index/results?PerPage=5&pageNum=1&what=".$number."&where=&rubrik=0&bezirk=0&orderBy=Standard&mapsearch=false", 5, undef, 1);
                if(not defined($result))
                {
                    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
                    {
                        $status = "timeout";
                        undef($result);
                    }
                }
                else
                {
                    #Log 2, $result;
                    if($result =~ /name\s+:\s+"(.+?)",/)
                    {
                        $invert_match = "";

                        while($result =~ /name\s+:\s+"(.+?)",/g)
                        {
                            $invert_match = $1 if(length($1) > length($invert_match));
                        }

                        $invert_match = AsteriskCM_html2txt($invert_match);
                        AsteriskCM_writeToCache($hash, $number, $invert_match);
                        undef($result);
                        return $invert_match;
                    }
                    elsif(not $result =~ /Es wurden keine passenden Eintr.ge gefunden/)
                    {
                        Log3 $name, 3, "AsteriskCM ($name): the reverse search result for $number could not be extracted from dasschnelle.at. Please contact the FHEM community.";
                    }
                    
                    $status = "unknown";
                }
            }
        }
        
    }
    
    if(AttrVal($name, "reverse-search-cache", "0") eq "1" and defined($status))
    { 
        # If no result is available set cache result and return undefined 
        $hash->{helper}{CACHE}{$number} = $status;
    }

    return "-";

}

#####################################
# replaces all HTML entities to their utf-8 counter parts.
sub AsteriskCM_html2txt($) {

    my ($string) = @_;

    $string =~ s/&nbsp;/ /g;
    $string =~ s/&amp;/&/g;
    $string =~ s/(\xe4|&auml;|\\u00e4|\\u00E4)/ä/g;
    $string =~ s/(\xc4|&Auml;|\\u00c4|\\u00C4)/Ä/g;
    $string =~ s/(\xf6|&ouml;|\\u00f6|\\u00F6)/ö/g;
    $string =~ s/(\xd6|&Ouml;|\\u00d6|\\u00D6)/Ö/g;
    $string =~ s/(\xfc|&uuml;|\\u00fc|\\u00FC)/ü/g;
    $string =~ s/(\xdc|&Uuml;|\\u00dc|\\u00DC)/Ü/g;
    $string =~ s/(\xdf|&szlig;)/ß/g;
    $string =~ s/<.+?>//g;
    $string =~ s/(^\s+|\s+$)//g;

    return trim($string);

}

#####################################
# writes reverse search result to the cache and if enabled to the cache file 
sub AsteriskCM_writeToCache($$$) {
    my ($hash, $number, $txt) = @_;
    my $name = $hash->{NAME};
    my $file = AttrVal($name, "reverse-search-cache-file", "");
    my $err;
    my @cachefile;
    my $phonebook_file;
  
    if(AttrVal($name, "reverse-search-cache", "0") eq "1")
    { 
        $file =~ s/(^\s+|\s+$)//g;
      
        $hash->{helper}{CACHE}{$number} = $txt;
      
        if($file ne "")
        {
            Log3 $name, 4, "AsteriskCM ($name): opening cache file $file for writing $number ($txt)";
            
            foreach my $key (keys %{$hash->{helper}{CACHE}})
            {
                push @cachefile, "$key|".$hash->{helper}{CACHE}{$key};
            }
            
            $err = FileWrite($file,@cachefile);
            
            if(defined($err) && $err)
            {
                Log3 $name, 2, "AsteriskCM ($name): could not write cache file: $err";
            }
        }
    }
}

#####################################
# loads the reverse search cache from file
sub AsteriskCM_loadCacheFile($;$)
{
    my ($hash, $file) = @_;

    my @cachefile;
    my @tmpline;
    my $count_contacts;
    my $name = $hash->{NAME};
    my $err;
    $file = AttrVal($hash->{NAME}, "reverse-search-cache-file", "") unless(defined($file));

    if($file ne "" and -r $file)
    { 
        delete($hash->{helper}{CACHE}) if(defined($hash->{helper}{CACHE}));
  
        Log3 $hash->{NAME}, 3, "AsteriskCM ($name): loading cache file $file";
        
        ($err, @cachefile) = FileRead($file);
        
        unless(defined($err) and $err)
        {      
            foreach my $line (@cachefile)
            {
                if(not $line =~ /^\s*$/)
                {
                    chomp $line;
                    @tmpline = split("\\|", $line, 2);
                    
                    if(@tmpline == 2)
                    {
                        $hash->{helper}{CACHE}{$tmpline[0]} = $tmpline[1];
                    }
                }
            }

            $count_contacts = scalar keys %{$hash->{helper}{CACHE}};
            Log3 $name, 2, "AsteriskCM ($name): read ".($count_contacts > 0 ? $count_contacts : "no")." contact".($count_contacts == 1 ? "" : "s")." from Cache"; 
        }
        else
        {
            Log3 $name, 3, "AsteriskCM ($name): could not open cache file: $err";
        }
    }
    else
    {
        Log3 $name, 3, "AsteriskCM ($name): unable to access cache file: $file";
    }
}

#####################################
# loads the reverse search cache from file
sub AsteriskCM_loadTextFile($;$)
{
    my ($hash, $file) = @_;

    my @file;
    my @tmpline;
    my $count_contacts;
    my $name = $hash->{NAME};
    my $err;
    $file = AttrVal($hash->{NAME}, "reverse-search-text-file", "") unless(defined($file));
  

    if($file ne "" and -r $file)
    { 
        delete($hash->{helper}{TEXTFILE}) if(defined($hash->{helper}{TEXTFILE}));
  
        Log3 $hash->{NAME}, 4, "AsteriskCM ($name): loading textfile $file";
        
        ($err, @file) = FileRead($file);
        
        unless(defined($err) and $err)
        {      
            foreach my $line (@file)
            {
                $line =~ s/#.*$//g;
                $line =~ s/\/\/.*$//g;
                
                
                if(not $line =~ /^\s*$/)
                {
                
                    chomp $line;
                    @tmpline = split(/,/, $line,2);
                    if(@tmpline == 2)
                    {
                        $hash->{helper}{TEXTFILE}{AsteriskCM_normalizePhoneNumber($hash, $tmpline[0])} = trim($tmpline[1]);
                    }
                }
            }

            $count_contacts = scalar keys %{$hash->{helper}{TEXTFILE}};
            Log3 $name, 4, "AsteriskCM ($name): read ".($count_contacts > 0 ? $count_contacts : "no")." contact".($count_contacts == 1 ? "" : "s")." from textfile"; 
        }
        else
        {
            Log3 $name, 3, "AsteriskCM ($name): could not open textfile: $err";
        }
    }
    else
    {
        @tmpline = ("###########################################################################################",
                    "# This file was created by FHEM and contains user defined reverse search entries          #",
                    "# Please insert your number entries in the following format:                              #",
                    "#                                                                                         #",
                    "#     <number>,<name>                                                                     #",
                    "#     <number>,<name>                                                                     #",
                    "#                                                                                         #",
                    "###########################################################################################",
                    "# e.g.",
                    "# 0123/456789,Mum",
                    "# +49 123 45 67 8,Dad",
                    "# 45678,Boss",
                    "####"
                    );                     
        $err = FileWrite($file,@tmpline);
        
        Log3 $name, 3, "AsteriskCM ($name): unable to create textfile $file: $err" if(defined($err) and $err ne "");
    }
}

sub AsteriskCM_normalizePhoneNumber($$) {

    my ($hash, $number) = @_;
    my $name = $hash->{NAME};
    
    my $area_code = AttrVal($name, "local-area-code", "");
    my $country_code = AttrVal($name, "country-code", "0049");
    

    $number =~ s/\s//g;                             # Remove spaces
    $number =~ s/^(\#[0-9]{1,10}\#)//g;             # Remove phone control codes
    $number =~ s/^\+/00/g;                          # Convert leading + to 00 country extension
    $number =~ s/[^*\d]//g if(not $number =~ /@/);  # Remove anything else isn't a number if it is no VoIP number
    $number =~ s/^$country_code/0/g;                # Replace own country code with leading 0



    if(not $number =~ /^0/ and not $number =~ /@/ and $area_code =~ /^0[1-9]\d+$/) 
    {
       $number = $area_code.$number;
    }   


    return $number;
}


1;
=pod
=begin html

<a name="AsteriskCM"></a>
<h3>AsteriskCM</h3>
<ul>
  <a name="AsteriskCMdefine"></a><br /><br />
	The module connects to Asterisk Manager Interface (AMI) and creates call events. You can use <a href="#FB_CALLLIST">FB_CALLLIST</a> with this module.
	<br /><br />
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; AsteriskCM &lt;server&gt; [&lt;user&gt; &lt;port&gt;]</code><br />
    <br />
    Default user is admin. Port is 5038 by default.
    <br />
  </ul>
  <br />
	<a name="AsteriskCMset"></a>
  <b>Set</b>
  <ul>
		<li><b>rereadCache</b> - Reloads the cache file if configured (see attribute: <a href="#reverse-search-cache-file">reverse-search-cache-file</a>)</li>
		<li><b>rereadTextfile</b> - Reloads the user given textfile if configured (see attribute: <a href="#reverse-search-text-file">reverse-search-text-file</a>)</li>
		<li><b>password</b> - set the AMI password </li>
		<li><b>newPassword</b> - replace the saved AMI password with another one.</li>
		Usage: <code>set &lt;name&gt; newPassword &lt;oldPassword&gt; &lt;newPassword&gt;</code>
		<li><b>reconnect</b> - disconnects and reconnects the connection to the AMI-Server</li>
	</ul>
  <br />
	<a name="AsteriskCMget"></a>
  <b>Get</b>
  <ul>
  <li><b>search &lt;phone-number&gt;</b> - returns the name of the given number via reverse-search (internal phonebook, cache or internet lookup)</li>
  <li><b>showCacheEntries</b> - returns a list of all currently known cache entries (only available when using reverse search caching funktionality)</li>
  <li><b>showTextfileEntries</b> - returns a list of all known entries from user given textfile (only available when using reverse search caching funktionality)</li>
  </ul>
  <br />
	<a name="AsteriskCMattr"></a>
	<b>Attributes</b><br /><br />
	<ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br />
		<li><a href="#do_not_notify">do_not_notify</a></li><br />
    <li><a name="disable">disable</a></li>
		Optional attribute to disable the Asterisk-Callmonitor. When disabled, the connection is closed and no phone events can be detected.
		<br /><br />
		Possible values: 0 => Asterisk-Callmonitor is activated, 1 => Asterisk-Callmonitor is deactivated.
		<br /><br />
		<li><a name="contextIncoming">contextIncoming</a></li>
		The Asterisk context for incoming calls<br /><br />
		<li><a name="contextOutgoing">contextOutgoing</a></li>
		The Asterisk context for outgoing calls<br /><br />
		<li><a name="reverse-search">reverse-search</a> (textfile,klicktel.de,dasoertliche.de,search.ch,dasschnelle.at)</li>
    Enables the reverse searching of the external number (at dial and call receiving).
    This attribute contains a comma separated list of providers which should be used to reverse search a name to a specific phone number. 
    The reverse search process will try to lookup the name according to the order of providers given in this attribute (from left to right). The first valid result from the given provider order will be used as reverse search result.
    <br /><br />per default, reverse search is disabled.<br /><br />
    <li><a name="reverse-search-cache">reverse-search-cache</a></li>
    If this attribute is activated each reverse-search result from an internet provider is saved in an internal cache
    and will be used instead of requesting each internet provider every time with the same number. The cache only contains reverse-search results from internet providers.<br /><br />
    Possible values: 0 => off , 1 => on<br />
    Default Value is 0 (off)<br /><br />
    <li><a name="reverse-search-cache-file">reverse-search-cache-file</a> &lt;file&gt;</li>
    Write the internal reverse-search-cache to the given file and use it next time FHEM starts.
    So all reverse search results are persistent written to disk and will be used instantly after FHEM starts.<br /><br />
    <li><a name="reverse-search-text-file">reverse-search-text-file</a> &lt;file&gt;</li>
    Define a custom list of numbers and their according names in a textfile. This file uses comma separated values per line in form of:
    <pre>
    &lt;number1&gt;,&lt;name1&gt;
    &lt;number2&gt;,&lt;name2&gt;
    ...
    &lt;numberN&gt;,&lt;nameN&gt;
    </pre>
    You can use the hash sign to comment entries in this file. If the specified file does not exists, it will be created by FHEM.
    <br /><br />
		<li><a name="remove-leading-zero">remove-leading-zero</a></li>
    If this attribute is activated, a leading zero will be removed from the external number (e.g. in telefon systems).<br /><br />
    Possible values: 0 => off , 1 => on<br />
    Default Value is 0 (off)<br /><br />
		<li><a name="local-area-code">local-area-code</a></li>
    Use the given local area code for reverse search in case of a local call (e.g. 0228 for Bonn, Germany)<br /><br />
    <li><a name="country-code">country-code</a></li>
    Your local country code. This is needed to identify phonenumbers in your phonebook with your local country code as a national phone number instead of an international one as well as handling Call-By-Call numbers in german speaking countries (e.g. 0049 for Germany, 0043 for Austria or 001 for USA)<br /><br />
    Default Value is 0049 (Germany)<br /><br />
	</ul>
	<br />
	<a name="AsteriskCMevents"></a>
  <b>Generated Events:</b><br><br>
  <ul>
  <li><b>event</b> (call|ring|connect|disconnect) - which event in detail was triggerd</li>
  <li><b>direction</b> (incoming|outgoing) - the call direction in general (incoming or outgoing call)</li>
  <li><b>external_number</b> - The participants number which is calling (event: ring) or beeing called (event: call)</li>
  <li><b>external_name</b> - The result of the reverse lookup of the external_number via internet. Is only available if reverse-search is activated. Special values are "unknown" (no search results found) and "timeout" (got timeout while search request). In case of an timeout and activated caching, the number will be searched again next time a call occurs with the same number</li>
  <li><b>internal_number</b> - The internal number (fixed line, VoIP number, ...) on which the participant is calling (event: ring) or is used for calling (event: call)</li>
  <li><b>internal_connection</b> - The internal connection (10,20,1000, ...) which is used to take or perform the call from sip.conf</li>
  <li><b>external_connection</b> - The external connection (SIP...) which is used to take or perform the call</li>
  <li><b>call_duration</b> - The call duration in seconds. Is only generated at a disconnect event. The value 0 means, the call was not taken by anybody.</li>
  <li><b>call_id</b> - The call identification number (UniqueID) to separate events of two or more different calls at the same time. This id number is equal for all events relating to one specific call.</li>
  <li><b>missed_call</b> - This event will be raised in case of a missing incoming call. If available, also the name of the calling number will be displayed.</li>
	<li><b>missed_call_name</b> - The name of the caller like in external_name.</li> 
  <li><b>missed_call_line</b> - Will be raised together with "missed_call". It shows the number of the internal line which received the missed call.</li> 
	<li><b>running_calls</b> - The number of running calls.</li> 
  </ul>
  <br>
  <b>Legal Notice:</b><br><br>
  <ul>
  <li>klicktel.de reverse search is powered by telegate MEDIA</li>
  </ul>
</ul>

=end html
=cut
