#!/usr/bin/perl 


use LWP::Simple;                # From CPAN
use JSON qw( decode_json );     # From CPAN
use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice
use Time::localtime;
use Time::Piece;
use LWP::UserAgent;
use Digest::SHA qw(hmac_sha512_hex);

use Poloniex;


#poloniuex
my $apikey = $ENV{'POLONIEX_APIKEY'};
my $sign = $ENV{'POLONIEX_SIGN'};

my $decoded_json;
my $hashref_temp = 0;

sub get_json;
sub timestamp;
sub trim;
sub get_json_post;

# $decoded_json=get_json("https://api.nicehash.com/api?method=orders.set.price&id=$apiid&key=$apikey&location=0&algo=$algo&order=$local_specific_order->{'id'}&price=$increase_price");
$decoded_json=get_json("https://poloniex.com/public?command=returnTicker");
# print Dumper $decoded_json;
foreach (keys (%{$decoded_json}))
{
	# 'percentChange' => '0.03412950',
	# 'low24hr' => '0.00036300',
	# 'last' => '0.00038057',
	# 'high24hr' => '0.00038800',
	# 'lowestAsk' => '0.00038055',
	# 'quoteVolume' => '91871.69002694',
	# 'baseVolume' => '34.51963175',
	# 'id' => 170,
	# 'highestBid' => '0.00037520',
	# 'isFrozen' => '0'
	
	if ( $_ =~ /BTC_(.*)/ )
	{
		# only trade against BTC
		my $coinName = $1;
		
		my $percentChange   = ${decoded_json}->{$_}->{'percentChange'};
		my $low24hr   = ${decoded_json}->{$_}->{'low24hr'};
		my $last   = ${decoded_json}->{$_}->{'last'};
		my $high24hr   = ${decoded_json}->{$_}->{'high24hr'};
		my $lowestAsk   = ${decoded_json}->{$_}->{'lowestAsk'};
		my $quoteVolume   = ${decoded_json}->{$_}->{'quoteVolume'};
		my $baseVolume   = ${decoded_json}->{$_}->{'baseVolume'};
		my $id   = ${decoded_json}->{$_}->{'id'};
		my $highestBid   = ${decoded_json}->{$_}->{'highestBid'};
		my $isFrozen   = ${decoded_json}->{$_}->{'isFrozen'};		
		
		if ( $isFrozen == 0 )
		{
		#only unfrozen pairs		
			if ( ( $percentChange >= 0.015 ) && ($percentChange <= 0.02) )
			{
				# get only the pair with a positive change in 24 hour, but the minimum of that
				if ( $hashref_temp == 0 )
				{
					$hashref_temp = \%{${decoded_json}->{$_}};				
					$hashref_temp->{'name'} = $coinName;
				}
				else
				{
					if ( $hashref_temp->{'percentChange'} >= $percentChange )
					{
						$hashref_temp = \%{${decoded_json}->{$_}};				
						$hashref_temp->{'name'} = $coinName;
					}
				}

				#only coins  with last24h change positive betweeen 1,5% and 2 %
				print "$coinName $last $isFrozen $percentChange\n";			
			}
		}

	}

}
	
# print " the minimum is  $hashref_temp->{'percentChange'} $hashref_temp->{'name'} \n";

# $decoded_json=get_json("https://poloniex.com/tradingApi ");
# print Dumper $decoded_json;

# get_json_post();
my $polo_wrapper = Poloniex->new($apikey,$sign);
my $balances = $polo_wrapper->get_balances();
foreach (sort (keys($balances)))
{
	
	print "test $_ $balances->{$_} \n";
}
# print Dumper $polo_wrapper->get_balances();
print Dumper $polo_wrapper->get_my_trade_history("all");
print Dumper $polo_wrapper->get_open_orders("all");

sub trim {
	my $input = shift;
	$input =~ s/^\s+|\s+$//g;
	return $input;
}


#gets url returns result object in json decoded  
sub get_json
{
	my $json;
	my $decode_json;
	my $url = shift;
	# 'get' is exported by LWP::Simple; install LWP from CPAN unless you have it.
	# You need it or something similar (HTTP::Tiny, maybe?) to get web pages.
	$json = get( $url );
	#sleep 250ms
	select(undef, undef, undef, 0.25);
	#print "curl --silent $url \n" ;
	#$json = `curl --silent $url`;
	warn "Could not get $url  !" unless defined $json;
	# print $json;

	# Decode the entire JSON
	$decode_json = decode_json( $json );
	return $decode_json

#	print Dumper $decoded_json;	
}

sub timestamp {
   my $t = localtime;
   return sprintf( "%04d-%02d-%02d_%02d-%02d-%02d",
                  $t->year, $t->mon, $t->mday,
                  $t->hour, $t->min, $t->sec );
	# %Y-%m-%d_%H-%M-%S				  
	# return localtime;
}


sub get_json_post 
{
	my $ua = LWP::UserAgent->new;
	my $nonce =  time();
	my $digest; 
	my $server_endpoint = "https://poloniex.com/tradingApi";
	 
	# set custom HTTP request header fields
	my $req = HTTP::Request->new(POST => $server_endpoint);
	# $req->header('content-type' => 'application/json');
	# $req->header('Content-Type' => 'application/x-www-form-urlencoded');
	# $req->header('Content-Type' => 'multipart/form-data');
	# $req->header('x-auth-token' => 'kfksj48sdfj4jd9d');
	$req->header('Key' => $apikey);
	# $req->header('x-auth-token' => 'kfksj48sdfj4jd9d');
	# add POST data to HTTP request body
	my $post_data = '{ "command": "returnBalances" , "nonce": "'.$nonce.'" }';

	$digest = hmac_sha512_hex($post_data,$sign);	 
	$req->header('Sign' => $digest);

	# print "$digest \n";
	$req->content($post_data);
	print Dumper $req;
	 
	my $resp = $ua->request($req);
	print Dumper $resp;
	if ($resp->is_success) {
		my $message = $resp->decoded_content;
		print "Received reply: $message\n";
	}
	else {
		print "HTTP POST error code: ", $resp->code, "\n";
		print "HTTP POST error message: ", $resp->message, "\n";
	}
}