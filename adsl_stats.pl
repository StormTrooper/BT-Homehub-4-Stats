#!/usr/bin/perl
#
# The original script was for the BT Home Hub 3 downloaded from here 
# http://ie.archive.ubuntu.com/disk1/disk1/download.sourceforge.net/pub/sourceforge/b/bt/bthubstats/
# No more development is being done on the scripts so had to do a bit of hacking to get it working on the BT Home Hub 4.
# I haven't been abble to get the attenuation/noise/power etc stats as it looks like these were removed.


# Script to download stats from a BT Home Hub 4

use warnings;
use strict;
use LWP::Simple;
use Digest::MD5;
use POSIX;


sub dump_req {
    print '------------------------'."\n";
    print $_[0]->as_string();
    print '------------------------'."\n";
}


sub convert_to_kb {
    my $size = shift;
    my ($num, $units) = split ' ', $size;

    if ($units eq 'MB') {
        $num *= 1024;
    } elsif ($units eq 'GB') {
        $num *= 1024 ** 2;
    } elsif ($units ne 'KB') {
        die "Unrecognized units: $units"
    }

    return "$num";
}

sub getpage {
#
# Retrieves a page. If it looks like the BT Home Hub is trying to force us
# to log on, then we have to mangle the input password with the Hub supplied
# javascript using a dynamic hashkey and MD5 encryption.
# Why BT think this extra security is necessary is anyone guess, because, if someone
# could grab your un-encrypted password, then they can grab the html/javascript and
# decrypt your encrypted password.
#
# arg1 = the page retreival agent
# arg2 = the page number (all pages appear to be numbered)
# arg3 non-zero prints debugging info
# arg4 = password
#

    my $agent=$_[0];
    my $url="http://192.168.1.1/index.cgi?active_page=$_[1]";

    #my $url="http://$router/$_[1].html";	    
    my $debug=$_[2];
    my $password=$_[3];

    if ($debug) {print "Retreiving url=$url\n";}

    my $request = HTTP::Request->new(GET => $url);
    my $response = $agent->request($request);
    if ($debug) { &dump_req($request);}

    my $c = $response->content();

    if ($response->is_success) {
	if ($debug) {print "Successfully retrieved\n"};
	if (index($c, 'Page(9142)=[Login]') != -1) {
	    if ($debug) {print "Login page detected\n";}
#
# Trawl the page setting up an associative array with all input fields,
# their names and current values
#
	    my $stuff="";           # holds the input field
	    my $txt='<INPUT ';
	    my $p=index($c, $txt, 1);
	    my $k;     # key
	    my $v;     # value
	    my $i=0;
	    my %vars;  # associative array

	    while ($p != -1){
		$stuff=substr($c, $p, index($c, '>', $p) -$p);
		if (index($stuff, 'type=HIDDEN') != -1 || index($stuff, 'type=PASSWORD') != -1) {
# Only want hidden input fields.
		    $i=index($stuff, 'name="')+6;
		    $k=index($stuff, '"', $i+1);
		    $k=substr($stuff, $i, $k-$i);

		    $i=index($stuff, 'value="')+7;
		    $v=index($stuff, '"', $i);
		    $v=substr($stuff, $i, $v-$i);
	
		    $vars{$k}=$v;
		}
		$p=index($c, $txt, $p + length($txt));
	    }
#
# Mangle the variables just like Javascript SendPassword() would have done.
# I've checked the output into md5_pass and it does produce the same
# output as JavaScript
#
	    $vars{"md5_pass"} = $password . $vars{"auth_key"};
	    my $tmp = Digest::MD5::md5_hex($vars{"md5_pass"});
	    $vars{"md5_pass"} = $tmp;

	    $vars{"mimic_button_field"}='submit_button_login_submit%3A+..';
	    $vars{"post_id"}=0;

	    if ($debug) {
		print "Contents of all hidden variables\n";
		while (($k, $v) = each(%vars)) {
		    print "$k = $v\n";
		}
	    }

# Create a new request - this'll end up with a redirection

	    my $postdata="";

	    while (($k, $v) = each(%vars)) {
		if (length($postdata) != 0) {
		    $postdata .='&';
		}
		$postdata=$postdata.$k.'='.$v;
	    }

	    $i=length($postdata);

	    my $new_req = HTTP::Request->new(POST => 'http://192.168.1.1/index.cgi');

	    $new_req->content_type('application/x-www-form-urlencoded');
	    $new_req->header(Accept => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
	    $new_req->header('content-length' => $i);

	    $new_req->header(DNT => "1");
	    $new_req->header(Connection => "keep-alive");
	    $new_req->referer('http://192.168.1.1/?active_page=9098');

	    $new_req->content($postdata);

	    my $res = $agent->request($new_req);
	    if ($debug) {&dump_req($new_req);}

# Check the outcome of the response

	    if ($res->is_success) {
		if ($debug) {print "SUCCESS !!\n".$res->content;}
		return $res->content;
	    } else {
		if ($res->status_line eq "302 Moved Temporarily") {

		    if ($debug) {print $res->status_line."\n";}
#
# Get the redirection and go there..
#

		    $c=$res->content;
		    my $xx=index($c, 'href=&quot;') + 11;
		    $stuff='http://192.168.1.1'.substr($c, $xx, index($c, '&gt;here&lt;') - $xx);
		    if ($debug) {print 'Redirected URL ='.$stuff."\n";}

		    my $req_two = HTTP::Request->new(GET => $stuff);
		    my $response = $agent->request($req_two);
		    my $c = $response->content();
		    if ($debug) { &dump_req($req_two); print $response->status_line."\n";};
		    return $c;
		}
 # Check the outcome of the response
		if ($res->is_success) {
		    return $res->content;
		    print $res->content;
		} else {
		    print $res->content."\n";
		    print $res->status_line."\n";
		}
	    }
	}
    } else {
	print $response->content."\n";
	print $response->status_line."\n";
    }
    return $c;
}
########################################################################
{


    my $password=$ARGV[0];
    my $file=$ARGV[1];

 #   $password = 'secret12' unless defined $password;

    my $agent = LWP::UserAgent->new();
    $agent->agent("Mozilla/5.0 (X11; Linux x86_64; rv:14.0) Gecko/20100101 Firefox/14.0.1");
    $agent->default_header('Accept-Encoding' => 'gzip, deflate');
    $agent->default_header('Accept-Language' => 'en-gb,en;q=0.5');

    $agent->cookie_jar( {} );

#
# Start with page 9117. (Home->Settings->(login)->Advanced settings->Broadband->Connection
# This page looks like ...
#
#ADSL Line Status
#Connection Information
#Line state:	Connected
#Connection time:	0 days, 19:42:50
#Downstream:	3.677 Mbps
#Upstream:	882 Kbps
# 
#ADSL Settings
#VPI/VCI:	0/38
#Type:	PPPoA
#Modulation:	G.992.5 Annex A
#Latency type:	Interleaved
#Noise margin (Down/Up):	6.9 dB / 5.0 dB
#Line attenuation (Down/Up):	44.8 dB / 27.8 dB
#Output power (Down/Up):	18.1 dBm / 12.6 dBm
#FEC Events (Down/Up):	270444037 / 29971
#CRC Events (Down/Up):	175 / 47
#Loss of Framing (Local/Remote):	0 / 0
#Loss of Signal (Local/Remote):	0 / 0
#Loss of Power (Local/Remote):	0 / 0
#HEC Events (Down/Up):	272 / 32
#Error Seconds (Local/Remote):	366769 / 25562

#
# need to get first page twice because of logins and cookies
    my $c = &getpage($agent, '9117', 0, $password);
    $c = &getpage($agent, '9117', 0, $password);
    my $txt='BT Home Hub 4';
    my $p=index($c,$txt,1);
    if ($p eq -1) { die  "Can't find $txt\n$c";}
    $p+=length($txt) + 2;
    my $currenttime=substr($c, $p, index($c, '<', $p) -$p);
# end of new code
    my $hhmm=substr($currenttime,0,5);
    my $dd=substr($currenttime,6,2);
    my $mm=substr($currenttime,9,2);
    my $yy=substr($currenttime,12,2);
    my $now="20".$yy.'-'.$mm.'-'.$dd.' '.$hhmm;
# Connection speeds (in kbps)
    $txt='Downstream:';
    $p=index($c,$txt,1);
	if ($p eq -1) { die  "I suspect your password $password is invalid\n";}
    $p+=length($txt) + 2;
    my $txt2='%">';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $dw_data_rate=substr($c, $p, index($c, '<', $p) -$p);
    $txt2 = ' Kbps';
    $p=index($dw_data_rate, $txt2, 1);
    if ($p ne -1) { $dw_data_rate = substr($dw_data_rate, 0, $p);}
    $txt2 = ' Mbps';
    $p=index($dw_data_rate, $txt2, 1);
    if ($p ne -1) { $dw_data_rate = substr($dw_data_rate, 0, $p) *1000;}

    $txt='Upstream:';
    $p=index($c,$txt,$p);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt) + 2;
    $txt2='%">';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $up_data_rate=substr($c, $p, index($c, '<', $p) -$p);

    $txt2 = ' Kbps';
    $p=index($up_data_rate, $txt2, 1);
    if ($p ne -1) { $up_data_rate = substr($up_data_rate, 0, $p);}
    $txt2 = ' Mbps';
    $p=index($up_data_rate, $txt2, 1);
    if ($p ne -1) { $up_data_rate = substr($up_data_rate, 0, $p) *1000;}

## Latency type
#
#    $txt='Latency type:';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt after $txt\n";}
#    $p+=length($txt2);
#    my $dw_latency=substr($c, $p, index($c, '<', $p) -$p);
#    my $up_latency=$dw_latency;
## Noise Margin
#
#    $txt='Noise margin (Down/Up):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $dw_snr_margin=substr($c, $p, index($c, ' dB', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $up_snr_margin=substr($c, $p, index($c, ' dB', $p) -$p);
#
## Line Attenuation
#
#    $txt='Line attenuation (Down/Up):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $dw_line_att=substr($c, $p, index($c, ' dB', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $up_line_att=substr($c, $p, index($c, ' dB', $p) -$p);
#
## Power
#
#    $txt='Output power (Down/Up):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $rx_pwr=substr($c, $p, index($c, ' dBm', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $tx_pwr=substr($c, $p, index($c, ' dBm', $p) -$p);
#
# # CRC events
#
#    $txt='CRC Events (Down/Up):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $dw_crc=substr($c, $p, index($c, ' ', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $up_crc=substr($c, $p, index($c, '<', $p) -$p);
#
# Loss of frame
#
#    $txt='Loss of Framing (Local/Remote):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $dw_losf=substr($c, $p, index($c, ' ', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $up_losf=substr($c, $p, index($c, '<', $p) -$p);
#
## Loss of signal
#
#    $txt='Loss of Signal (Local/Remote):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $dw_loss=substr($c, $p, index($c, ' ', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $up_loss=substr($c, $p, index($c, '<', $p) -$p);
#
## Error seconds
#
#    $txt='Error Seconds (Local/Remote):';
#    $p=index($c,$txt,$p);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $dw_err_secs=substr($c, $p, index($c, ' ', $p) -$p);
#
#    $txt2=' / ';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $up_err_secs=substr($c, $p, index($c, '<', $p) -$p);
#
# Try and get character sent/received. For the BT Homehub, this
# is not an actual character count but is rounded to GB
# The page looks a bit like this ..
#		
#Internet Connection Configuration
#Connection Information
#Connection time:	1 days, 04:16:44	 
#Data Transmitted/Received (GB):	0.1 / 0.5	 
#Broadband username:	bthomehub@btbroadband.com	 
#Password:	Not configured	 
# 
#TCP/IP settings
#Broadband network IP address:	xxx.xxx.xxx.xxx	 
#Default gateway:	xxx.xxx.xxx.xxx
#Primary DNS:	xxx.xxx.xxx.xxx	 
#Secondary DNS:	xxx.xxx.xxx.xxx	 
 
    $c = &getpage($agent, '9116', 0, $password);
#
# try and find the 'uptime'
# Connection time (aka $uptime)

    $txt='wait = ';
    $p=index($c,$txt,1);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt);
    my $uptime=substr($c, $p, index($c, ';', $p) -$p);
    my $hh=floor($uptime / 3600);
    $uptime -=$hh*3600;
    $mm=floor($uptime / 60);
    my $ss=$uptime - ($mm * 60);
    $uptime=sprintf("%d:%02d:%02d", $hh, $mm, $ss);

    $txt='Data Transmitted/Received:';
    $p=index($c,$txt,$p);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt) + 2;
    $txt2='MIDDLE>';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $tx_bytes=substr($c, $p, index($c, ' ', $p) -$p+3);
    $tx_bytes = convert_to_kb($tx_bytes);
    $txt2=' / ';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $rx_bytes=substr($c, $p, index($c, '<', $p) -$p);
    $rx_bytes = convert_to_kb($rx_bytes);
    $txt='Broadband network IP address:';
    $p=index($c,$txt,$p);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt) + 2;
    $txt2='%">';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $ip_addr=substr($c, $p, index($c, '<', $p) -$p);

    $txt='Default gateway:';
    $p=index($c,$txt,$p);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt) + 2;
    $txt2='%">';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $gateway=substr($c, $p, index($c, '<', $p) -$p);
    $txt='Primary DNS:';
    $p=index($c,$txt,$p);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt) + 2;
    $txt2='%">';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $dns_1=substr($c, $p, index($c, '<', $p) -$p);

    $txt='Secondary DNS:';
    $p=index($c,$txt,$p);
    if ($p eq -1) { die  "Can't find $txt\n";}
    $p+=length($txt) + 2;
    $txt2='%">';
    $p=index($c,$txt2,$p);
    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
    $p+=length($txt2);
    my $dns_2=substr($c, $p, index($c, '<', $p) -$p);

#		
#Hub Firmware Information
#Current firmware:	Version 4.7.5.1.83.8.57.1.3 (Type A)
#Last updated:	18/06/11
#    $c = &getpage($agent, '9123', 0, $password);
#

#    $txt='Current firmware:';
#    $p=index($c,$txt,1);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
#    $p+=length($txt2);
#    my $firmware=substr($c, $p, index($c, '<', $p) -$p);
#
#    $txt='Last updated:';
#    $p=index($c,$txt,1);
#    if ($p eq -1) { die  "Can't find $txt\n";}
#    $p+=length($txt) + 2;
#    $txt2='%">';
#    $p=index($c,$txt2,$p);
#    if ($p eq -1) { die  "Can't find $txt2 after $txt\n";}
 #   $p+=length($txt2);
#    my $firmware_updated=substr($c, $p, index($c, '<', $p) -$p);

    my $startups="";

    my $o_file='>>'.$file;

    my $header=0;
    unless (-e $file) {
	$header=1;
    }

    open(OUT,$o_file) or die "Couldn't open output file";

    if ($header) {
	print OUT "I/P Address,Default Gateway,Primary DNS,Secondary DNS,Down data Rate (kbps),Up data Rate(kbps),Down latency,Up Latency,Bytes Sent,Bytes Received,Startup Attempts,Firmware Version,Firmware Updated\n";
    }

    print OUT "$ip_addr,$gateway,$dns_1,$dns_2,$dw_data_rate,$up_data_rate,$tx_bytes,$rx_bytes,$startups\n";

    close(OUT);
}

