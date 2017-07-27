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
use Switch;

use Poloniex;


#poloniuex
my $apikey = $ENV{'POLONIEX_APIKEY'};
my $sign = $ENV{'POLONIEX_SIGN'};

my $decoded_json;
my $hashref_temp = 0;

my $previous_price = 0;
my $has_pending_order = 0; # bit to see if there is a pending order ot not
my $crt_order_number = 0; # in case there is a pending order, this should express the order number
my $crt_pair = 0; # the current pair in the order
my $crt_tstmp = 0; # the tstmp of the current order
my $crt_price = 0; # the current price in the order
my $crt_ammount = 0; # the current ammount in the order
my $current_spike = 0; # the current number of buy/sell 
my $btc_balance = 0.001; # the ammount in BTC
my @queue_pairs_lists; # list with all samplings
my $queue_pairs_lists_size = 5; # size of the list with all samplings
my $wining_procent = 1.5; # the procent where we sell
my $wining_procent_divided = $wining_procent / 100; # the procent where we sell
my $down_delta_procent_threshold =  2; # the procent from max win down
my $filename_status= "poloniex_status.ctrl";
my $filename_status_h;

my $filename_selling= "poloniex_selling.ctrl";
my $filename_selling_h;


my $filename_samplings= "poloniex_samplings.ctrl";
my $filename_samplings_h;

my $sleep_interval = 10; # sleep interval in seconds , the default
my $step_wait_execute = 10; # number of seconds to wait until verify if the order is executed
my $step_wait_selling = 10;
my $step_wait_sell_execute = 30;
my $step_sampling = 80; # number of seconds between samples when deciding to buy


my $loosingProcent = 20; #the loss limit
my $volumeRef = 70; # only pairs with more then x coin volume

# BUYING 1
# BOUGHT 2
# SELLING 3
# SOLD 4



sub get_json;
sub timestamp;
sub trim;
sub get_state_machine;
sub get_pair_list;
sub get_next_buy_ticker;

sub get_tstmp;
sub get_percentChange;
sub get_low24hr;
sub get_last;
sub get_high24hr;
sub get_lowestAsk; 
sub get_quoteVolume;
sub get_baseVolume;
sub get_id; 
sub get_highestBid;
sub get_isFrozen;

# get_json_post();
my $polo_wrapper = Poloniex->new($apikey,$sign);
# my $balances = $polo_wrapper->get_balances();
# foreach (sort (keys($balances)))
# {
	
	# print "test $_ $balances->{$_} \n";
# }
 # print Dumper $polo_wrapper->get_balances();
# print Dumper $polo_wrapper->get_my_trade_history("BTC_POT");
# print Dumper $polo_wrapper->get_open_orders("all");
# print Dumper $polo_wrapper->get_open_orders("all");						

 # exit 0;
while (1)
{
							# $decoded_json = $polo_wrapper->get_my_trade_history("BTC_XBC");
							# foreach (@{$decoded_json})
							# {
								
								# print "elem $_->{'orderNumber'} \n";
							# }
							# exit 0;	

	# get the state machine
	my $execute_crt_tstmp = timestamp();
	my $state = get_state_machine();
	
	#switch for each state
	switch ($state) {
	case 1 { 
					print "BUYING \n";
					my $order_is_not_complete = 0;
					if ( $has_pending_order == 1 )
					{
						print "Order $crt_order_number is pending.Wait for finalization.\n";
						# print Dumper $polo_wrapper->get_open_orders("all");						
						$decoded_json = $polo_wrapper->get_open_orders("all");
						# print "ref is ".ref($decoded_json)." \n";
						# print Dumper $decoded_json;
						foreach (@{$decoded_json->{$crt_pair}})
						{
							if ( $_->{'orderNumber'} == $crt_order_number )
							{
									#we found the order in the pending list
									#order is not complete;
									$order_is_not_complete = 1;
							}
						}
						if ( $order_is_not_complete == 0 )
						{
							print "Order is completed ! \n";
							
							$decoded_json = $polo_wrapper->get_my_trade_history($crt_pair);
							print Dumper $decoded_json;
							my $total_btc = 0;
							my $buy_ammount = 0;
							foreach (@{$decoded_json})
							{
								if ( $crt_order_number == $_->{'orderNumber'} )
								{
									my $applied_fee = $_->{'amount'} - ( $_->{'amount'} * $_->{'fee'});
									$total_btc += $_->{'total'};
									$buy_ammount += $applied_fee;
								}
							}
							$sleep_interval = $step_wait_execute;
							
							#clear the selling file
							open(my $filename_selling_h, '>', $filename_selling) or warn "Could not open file '$filename_selling' $!";
							close $filename_selling_h;								
							
							# store the bought event
							print "$current_spike $crt_tstmp BOUGHT $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$buy_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";						
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h "$current_spike $crt_tstmp BOUGHT $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$buy_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";												
							close $filename_status_h;									
						}
						else
						{
							print "Order is not completed ! \n";						
						}
					}
					else
					{
						# there is no order
						# print "there is no order \n";
						my $buy_ticker = get_next_buy_ticker();
						if ( $buy_ticker ne "WRONG" )
						{
							print "buy now \n";
							# buy now
							# write status file - last line
							my $price = get_last($queue_pairs_lists[ $queue_pairs_lists_size - 1]->{$buy_ticker});

							if ( $price > 0.00001000 )
							{
								$price = $price + 0.00000010;								
							}
							else
							{
								# just increase with the small resolution
								$price = $price + 0.00000001;							
							}
							my $buy_ammount = $btc_balance / $price ;
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							$current_spike++;

							$decoded_json = $polo_wrapper->buy("BTC_$buy_ticker",$price,$buy_ammount);
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							 # print Dumper $polo_wrapper->buy("BTC_$buy_ticker",$price,$buy_ammount);
							# print "Buying \n";
							# print Dumper $decoded_json;
							$crt_order_number = $decoded_json->{'orderNumber'};
							print "$current_spike $execute_crt_tstmp BUYING BTC_$buy_ticker ".sprintf("%0.8f",$price)." $buy_ammount $crt_order_number $btc_balance \n";
							open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
							print $filename_status_h  "$current_spike $execute_crt_tstmp BUYING BTC_$buy_ticker ".sprintf("%0.8f",$price)." $buy_ammount $crt_order_number $btc_balance \n";
							close $filename_status_h;
							$sleep_interval = $step_wait_selling;
						}
						else
						{
						$sleep_interval = $step_sampling;
						}
					}
			}
	case 2 { 
					print "BOUGHT \n"; 

					# check if the current price is higher then bought price
					my %pairs_list = get_pair_list();

					my $sell_ticker = $crt_pair;
					$sell_ticker =~ s/BTC_(.*)/$1/g ;
					# print Dumper $pairs_list{$sell_ticker};					
					my $latest_price = get_last($pairs_list{$sell_ticker});
					# print "latest_price $latest_price\n";

					if ($latest_price > $crt_price )
					{
						my $delta = $latest_price - $crt_price;
						my $procent = (100 * $delta) / $crt_price;
						print "$sell_ticker $latest_price ".get_tstmp($pairs_list{$sell_ticker})." delta_procent $procent \n";
						if ( $procent >= $wining_procent )
						{
							open(my $filename_selling_h, '<', $filename_selling) or warn "Could not open file '$filename_selling' $!";
							my $last_line;
							$last_line = $_,while (<$filename_selling_h>);
							close $filename_selling_h;
							chomp($last_line);
							
							if ( $last_line =~ /^$/ )
							{
								print "$filename_selling is empty !!\n";						
								$previous_price = $latest_price;
							}
							else
							{
								$previous_price = $last_line;
							}
							
							if ( $previous_price > $latest_price )
							{
								# we went over the top and going down
								my $down_delta = $previous_price - $latest_price;
								my $down_delta_procent =  ( $down_delta * 100 ) / $previous_price ;
								
								if ( $down_delta_procent >= $down_delta_procent_threshold )
								{
									# we went down to much
									#it is time to sell
									if ( $latest_price > 0.00001000 )
									{

										$latest_price = $latest_price - 0.00000010;								
									}
									else
									{
										# just decrease with the small resolution
										$latest_price = $latest_price - 0.00000001;							
									}

									$decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
									$crt_order_number = $decoded_json->{'orderNumber'};
									# print Dumper $decoded_json;
									my $btc_after_sell = $latest_price * $crt_ammount;
									$btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
									print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
									open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
									print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
									close $filename_status_h;					
									$sleep_interval = $step_wait_execute;									
								}
								else
								{
									print "let it go down $sell_ticker $latest_price $procent $down_delta_procent\n";
								}
							}
							else
							{
								print "let it raise  $sell_ticker $latest_price $procent \n";
								open(my $filename_selling_h, '>', $filename_selling) or warn "Could not open file '$filename_selling' $!";
								print $filename_selling_h "$latest_price\n";
								close $filename_selling_h;									
							}
							$sleep_interval = $step_wait_selling;						
						}
						else
						{
							print "Not reached the wining procent $sell_ticker $latest_price  $crt_price $procent \n";
						}
					}
					else
					{
						my $delta = $crt_price - $latest_price;
						my $procent = (100 * $delta) / $crt_price;
						print "price smaller then bought price $sell_ticker $latest_price  $crt_price -$procent  \n";						
						$sleep_interval = $step_wait_selling;					
					}
					
					#case 2
					#make a price higher with 1.5 %
					#sell with that price and wait for the execution
					# my $latest_price = $crt_price + ( $crt_price * $wining_procent);
					# $decoded_json = $polo_wrapper->sell("BTC_$sell_ticker",$latest_price,$crt_ammount);
					# $crt_order_number = $decoded_json->{'orderNumber'};
					# # print Dumper $decoded_json;
					# my $btc_after_sell = $latest_price * $crt_ammount;
					# $btc_after_sell = $btc_after_sell - ( $btc_after_sell * 0.0015 );
					# print "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
					# open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					# print $filename_status_h "$current_spike $execute_crt_tstmp SELLING BTC_$sell_ticker ".sprintf("%0.8f",$latest_price)." $crt_ammount $crt_order_number $btc_after_sell \n";
					# close $filename_status_h;					
					# $sleep_interval = $step_wait_selling;
		    }	
	case 3 { 
					print "SELLING \n";
					my $sell_ticker = $crt_pair;
					my $order_is_not_complete = 0;
					$sell_ticker =~ s/BTC_(.*)/$1/g ;
					my %current_list = 	get_pair_list();
					# print Dumper $current_list{$sell_ticker};
					my $ticker_status = $current_list{$sell_ticker};
					$ticker_status =~ s/\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+.*/$1/g;
					
					$decoded_json = $polo_wrapper->get_open_orders("all");
					# print "ref is ".ref($decoded_json)." \n";
					# print Dumper $decoded_json;
					foreach (@{$decoded_json->{$crt_pair}})
					{
						if ( $_->{'orderNumber'} == $crt_order_number )
						{
								#we found the order in the pending list
								#order is not complete;
								$order_is_not_complete = 1;
						}
					}					
					
					if ( $order_is_not_complete == 0 )
					{
						print "Order is completed ! \n";
						
						$decoded_json = $polo_wrapper->get_my_trade_history($crt_pair);
						print Dumper $decoded_json;
						my $total_btc = 0;
						my $sell_ammount = 0;
						foreach (@{$decoded_json})
						{
							if ( $crt_order_number == $_->{'orderNumber'} )
							{
								my $applied_fee = $_->{'total'} - ( $_->{'total'} * $_->{'fee'} );
								$total_btc += $applied_fee;
								$sell_ammount += $_->{'amount'};
							}
						}						
						$sleep_interval = $step_wait_execute;
						print "$current_spike $crt_tstmp SOLD $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$sell_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";						
						open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
						print $filename_status_h "$current_spike $crt_tstmp SOLD $crt_pair ".sprintf("%0.8f",$crt_price)." ".sprintf("%0.8f",$sell_ammount)." $crt_order_number ".sprintf("%0.8f",$total_btc)." \n";												
						close $filename_status_h;		
					}
					else
					{
						my $delta_procent = 0;
						# my $bought_price = $crt_price - (
						if  ( $crt_price > $ticker_status )
						{
						$delta_procent = $crt_price - $ticker_status;
						$delta_procent = ( $delta_procent * 100 ) / $crt_price; 
						$delta_procent = $delta_procent * (-1) ;						
						}
						else
						{
						$delta_procent = $ticker_status - $crt_price;
						$delta_procent = ( $delta_procent * 100 ) / $crt_price; 
						}
						print "$execute_crt_tstmp Order is not completed ! delta is $delta_procent %  $crt_price  $ticker_status \n";	
						$sleep_interval = $step_wait_sell_execute;							
					}					
			}
	case 4 { 
					print "SOLD \n"; 
					print "$current_spike $crt_tstmp BUYING 0 0 0 0 $btc_balance \n";
					open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					print $filename_status_h "$current_spike $crt_tstmp BUYING 0 0 0 0 $btc_balance \n";
					close $filename_status_h;				
					$sleep_interval = $step_sampling;
			}	
	else { print "State is not recognised ! \n"; } 
	}
	sleep $sleep_interval;
}


	
# print " the minimum is  $hashref_temp->{'percentChange'} $hashref_temp->{'name'} \n";

# $decoded_json=get_json("https://poloniex.com/tradingApi ");
# print Dumper $decoded_json;



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

sub get_state_machine {
	my $previous_state = 0;
	#read status file - last line
	open(my $filename_status_h, '<', $filename_status) or warn "Could not open file '$filename_status' $!";
	my $last_line;
	$last_line = $_,while (<$filename_status_h>);
	close $filename_status_h;
	chomp($last_line);
	
	if ( $last_line =~ /^$/ )
	{
		print "$filename_status is empty !!\n";
		$previous_state = "BUYING";
		$has_pending_order = 0;		
		$current_spike = 0;
		$crt_order_number = 0;
		$crt_pair = 0;
		$crt_price = 0;
		$crt_ammount = 0;
		$crt_tstmp = 0;
	}
	else
	{
		# extract state   crt tstmp state pair price ammount ordernumber btc_balance
		if ( $last_line =~ /\s*?(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s/ )
		{

			$current_spike = $1;
			$crt_tstmp = $2;
			$previous_state = $3;
			$crt_order_number = $7;
			$crt_pair = $4;
			$crt_price = $5;
			$crt_ammount = $6;
			$btc_balance = $8;

			if  ($crt_order_number == 0 )
			{
				$has_pending_order = 0;
			}
			else
			{
				$has_pending_order = 1;
			}
		}
	}
	#get state machine
	
	switch ($previous_state) {
	case "BUYING"		{ return 1; }
	case "BOUGHT"	{ return 2; }
	case "SELLING"	{ return 3; }
	case "SOLD"	{ return 4; }
	else		{ print "Case not detected !! \n" ; return 0; }
    }	
}

sub get_pair_list {
	my %current_list;
	my $tstmp = timestamp();
	# $decoded_json=get_json("https://api.nicehash.com/api?method=orders.set.price&id=$apiid&key=$apikey&location=0&algo=$algo&order=$local_specific_order->{'id'}&price=$increase_price");
	$decoded_json=get_json("https://poloniex.com/public?command=returnTicker");
	# print Dumper $decoded_json;
	foreach (sort (keys (%{$decoded_json})))
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
				if ( $baseVolume > $volumeRef)
				{
					# only higher then a threshold
					if ( $last > 0.00001000 )
					{
						# if ( ( $percentChange >= 0.015 ) && ($percentChange <= 0.02) )
						# {
							# get only the pair with a positive change in 24 hour, but the minimum of that
							# if ( $hashref_temp == 0 )
							# {
								# $hashref_temp = \%{${decoded_json}->{$_}};				
								# $hashref_temp->{'name'} = $coinName;
							# }
							# else
							# {
								# if ( $hashref_temp->{'percentChange'} >= $percentChange )
								# {
									# $hashref_temp = \%{${decoded_json}->{$_}};				
									# $hashref_temp->{'name'} = $coinName;
								# }
							# }

							# only coins  with last24h change positive betweeen 1,5% and 2 %
							# print "$coinName $last $isFrozen $percentChange\n";			
						# }
						# push @elem $tstmp;
						# push @elem $coinName;
						# push @elem $percentChange;
						# push @elem $low24hr;
						# push @elem $last;
						# push @elem $high24hr;
						# push @elem $lowestAsk;
						# push @elem $quoteVolume;
						# push @elem $baseVolume;
						# push @elem $id;
						# push @elem $highestBid;
						# push @elem $isFrozen;
						$current_list{$coinName} = "$tstmp $percentChange $low24hr $last $high24hr $lowestAsk $quoteVolume $baseVolume $id $highestBid $isFrozen";
						# push @current_list, %elem_hash;				
					}
				}
			}
		}
	}
				
				# push @current_list, @elem;	
	return %current_list;
}


sub get_next_buy_ticker
{
	my $highest_negative_delta = 0;
	my $decline_ticker = "WRONG";
	populate_queue();
	if ( $#queue_pairs_lists < ($queue_pairs_lists_size - 1) )
	{
		print "we don't have a full sample list yet !\n";
		return $decline_ticker;
	}
	
	# print Dumper @queue_pairs_lists;
	foreach (sort (keys ($queue_pairs_lists[$queue_pairs_lists_size - 1 ])))
	{
		my $ticker = $_;
		my $isTickerGood = 0;
		
		my $first_tstmp = get_tstmp($queue_pairs_lists[ 0 ]->{$ticker});
		my $previous_tstmp = get_tstmp($queue_pairs_lists[ $queue_pairs_lists_size - 2  ]->{$ticker});
		my $last_tstmp = get_tstmp($queue_pairs_lists[ $queue_pairs_lists_size - 1  ]->{$ticker});
		# print "first $first_tstmp last $last_tstmp \n";		
		my $firstTime = Time::Piece->strptime($first_tstmp,'%Y-%m-%d_%H-%M-%S');
		my $previousTime = Time::Piece->strptime($previous_tstmp,'%Y-%m-%d_%H-%M-%S');
		my $lastTime = Time::Piece->strptime($last_tstmp,'%Y-%m-%d_%H-%M-%S');
		
		if ( ($lastTime - $firstTime) > (($step_sampling  * $queue_pairs_lists_size ) + 20) )
		{
			print "the time distance between the first and last sample is to high ".($lastTime - $firstTime)." \n";
			return $decline_ticker;
		}
		
		if  (  ($lastTime - $previousTime) < $step_sampling )
		{
			print "distance from the last to previous is to small \n";
			return $decline_ticker;
		}

		for (my $i = 0; $i < ($queue_pairs_lists_size - 1) ; $i++)
		{	
			 if ( get_last($queue_pairs_lists[ $i ]->{$ticker}) < get_last($queue_pairs_lists[ $i+1 ]->{$ticker}))
			 {
			  # print "$_ ".get_last($queue_pairs_lists[ $i ]->{$ticker})." < ".get_last($queue_pairs_lists[ $i+1 ]->{$ticker})." \n";
				#this is not a good ticker
				$isTickerGood = 1;
				last;
			 }
		}		
		if ( $isTickerGood == 1 )
		{
			# thicker is not good
			next;
		}
		
		my $first = get_last($queue_pairs_lists[ 0 ]->{$ticker});
		my $last  = get_last($queue_pairs_lists[ $queue_pairs_lists_size - 1  ]->{$ticker});
		
		my $low24hr = get_low24hr($queue_pairs_lists[ $queue_pairs_lists_size - 1  ]->{$ticker});
		my $high24hr = get_high24hr($queue_pairs_lists[ $queue_pairs_lists_size - 1  ]->{$ticker});		
		
		# only pairs at which the current price is between (lowest24h + 2.5%) and (highest24 - 2.5%) 
		if  ( ( $last >= ($low24hr + ($low24hr * ($wining_procent_divided + 0.02) ) ) ) && ( $last <= ($high24hr - ($high24hr * ($wining_procent_divided + 0.02) ) ) ) )  
		{
			# print "$ticker ";
			if  ( $first >= $last  )
			{
				my $delta = $first - $last;
				my $procent = (100 * $delta) / $first;
				if ( $highest_negative_delta < $procent )
				{
					$highest_negative_delta  = $procent;
					$decline_ticker = $ticker;
				}
				# print "DOWN  $procent  $first $last";
			}
			else
			{
				my $delta = $last - $first;
				my $procent = (100 * $delta) / $first;
				# print "UP $procent $first $last";
			}		
		}		
		
		

		# for (my $i = 0; $i < $queue_pairs_lists_size ; $i++)
		# {	
			# print get_last(@queue_pairs_lists[ $i ]->{$ticker})." ";
		# }
		# print "\n";
		# print "tstmp 0  and 1 is for $_  ".get_tstmp(@queue_pairs_lists[ 0 ]->{$_})."  ".get_tstmp(@queue_pairs_lists[ 1 ]->{$_})."  ".get_tstmp(@queue_pairs_lists[ 2 ]->{$_})."  ".get_tstmp(@queue_pairs_lists[ 3 ]->{$_})." \n";
	}
	if ( $decline_ticker eq "WRONG" )
	{
		print "There is no good ticker $decline_ticker!\n";
	}
	else
	{
		print "the most declining ticker is $decline_ticker $highest_negative_delta ".get_last($queue_pairs_lists[ 0 ]->{$decline_ticker})." ".get_last($queue_pairs_lists[ $queue_pairs_lists_size - 1  ]->{$decline_ticker})." ".get_tstmp($queue_pairs_lists[ 0 ]->{$decline_ticker})." ".get_tstmp($queue_pairs_lists[ $queue_pairs_lists_size - 1  ]->{$decline_ticker})."\n";	
	}
	return $decline_ticker;
	# foreach (@queue_pairs_lists)
	# {
		# my $hash = $_;
		# foreach (sort (keys (%{$hash})))
		# {
			# print "$_ $hash->{$_} \n";
		# }
	# }
	
}

sub populate_queue
{
	#clear the list
	foreach (@queue_pairs_lists)
	{
		shift @queue_pairs_lists;
	}

	# read the sampling files and loadit in RAM
	my %tmp_hash_chunk;	
	my $start_chunk = 0;
	open $filename_samplings_h, $filename_samplings or warn "Could not open $filename_samplings: $!";

	while( my $line = <$filename_samplings_h>)  {   
		chomp($line);
		
		if ( $start_chunk == 1 )
		{
			if ( $line =~ /.*STOP.*/ )
			{
				#stop
				$start_chunk = 0;
				# print Dumper %tmp_hash_chunk;
				my %chunk_hash = %tmp_hash_chunk;
				push @queue_pairs_lists , \%chunk_hash;
				# print Dumper @queue_pairs_lists;

				if ( ($#queue_pairs_lists + 1) > $queue_pairs_lists_size )
				{
					# the queue is full
					# remove the oldest element
					shift @queue_pairs_lists;
				}
				#clear the hash
				delete $tmp_hash_chunk{$_} for keys %tmp_hash_chunk;
			}
			else
			{
				# every line here is good
				# print "add to chunk \n";
				# print "$line \n";
				if ( $line =~ /(\S*?)\s+?(.*)$/ )
				{
					# print "[$1] [$2] \n";
					$tmp_hash_chunk{$1} = $2;
				}
			}
		}
		if ( $line =~ /.*START.*/ )
		{
			#starts
			$start_chunk = 1;
		}
	}

	close $filename_samplings_h;

	# print Dumper @queue_pairs_lists;
	
	# push the new sampling
	my %current_list = 	get_pair_list();

	push @queue_pairs_lists, \%current_list;	
	if ( ($#queue_pairs_lists + 1) > $queue_pairs_lists_size )
	{
		# the queue is full
		# remove the oldest element
		# print "before unqueue $#queue_pairs_lists \n";
		# print Dumper @queue_pairs_lists;
		shift @queue_pairs_lists;
		# print "after unqueue $#queue_pairs_lists \n";
		# print Dumper @queue_pairs_lists;
	}

	#rewrite the file with the new samplings
	open($filename_samplings_h, '>', $filename_samplings) or warn "Could not open file '$filename_samplings' $!";
	foreach (@queue_pairs_lists)
	{
		# print $filename_samplings_h "START \n";	
		# print $filename_samplings_h "$_ \n";
		# print $filename_samplings_h "STOP \n";
		my $chunk = $_;
		print $filename_samplings_h "START \n";
		foreach (sort (keys(%{$chunk})) )
		{
			print $filename_samplings_h "$_ $chunk->{$_} \n";						
		}
		print $filename_samplings_h "STOP \n";
	}

	close $filename_samplings_h;
}


sub get_tstmp
{
	my $param = shift;
	if ( $param =~ /(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}

sub get_percentChange
{
	my $param = shift;
	if ( $param =~ /\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_low24hr
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_last
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_high24hr
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_lowestAsk
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_quoteVolume
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_baseVolume
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_id
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_highestBid
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?)\s+\S*?.*/ )
	{
		return $1;
	}
}
sub get_isFrozen
{
	my $param = shift;
	if ( $param =~ /\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+\S*?\s+(\S*?).*/ )
	{
		return $1;
	}
}
