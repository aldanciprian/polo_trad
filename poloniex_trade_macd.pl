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
use File::Basename;
use threads;
use threads::shared;
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
my $queue_pairs_lists_size = 30; # size of the list with all samplings
my $wining_procent = 1.1; # the procent where we sell
my $wining_procent_divided = $wining_procent / 100; # the procent where we sell
my $down_delta_procent_threshold =  0.23; # the procent from max win down
my $basename = basename($0,".pl");;
my $sample_minutes = 5; # number of minutes between each sample
my $max_distance =  ($sample_minutes*60)+ 60; # maximum distance between 2 samples in seconds
my $min_distance =  ($sample_minutes*60) - 60; # minimum distance between 2 samples in seconds


my $filename_status= $basename."_status.ctrl";
my $filename_status_h;

my $filename_selling= $basename."_selling.ctrl";
my $filename_selling_h;


my $filename_samplings= $basename."_samplings.ctrl";
my $filename_samplings_h;

my $filename_samplings_all = $basename."_samplings_all.ctrl";
my $filename_samplings_all_h;

my $filename_macd= $basename."_macd.ctrl";
my $filename_macd_h;


my $sleep_interval = 10; # sleep interval in seconds , the default
my $step_wait_execute = 10; # number of seconds to wait until verify if the order is executed
my $step_wait_selling = 10;
my $step_wait_sell_execute = 30;
my $step_sampling = 10; # number of seconds between samples when deciding to buy
my $step_sampling_ctr = 0; # counter for macd samplings
my $step_sampling_ctr_size = (280 / $step_sampling); # counter for macd samplings

my $loosingProcent = 20; #the loss limit
my $volumeRef = 70; # only pairs with more then x coin volume

my $buy_timeout = 0; #if it doesn't buy...cancel the order
my $runOnce = 0;
my $runOnce_3day = 0;
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




# my $thr_sampling;
# sub sampling_thread
# {
	# while (1)
	# {
	# my $thread_tstmp =  timestamp();
	# print "========================== From sampling thread $thread_tstmp $$=============================\n";
	# populate_queue();
	# get_next_buy_ticker($crt_pair);
	# my $sampling_interval = $step_sampling;
	# sleep $sampling_interval;
	# }
# }


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

# $thr_sampling = threads->create('sampling_thread');
	
# $thr_sampling->join();
 # exit 0;
 sub test;
while (1)
{
	my $execute_crt_tstmp = timestamp();
	# test();
	print "============================= ".basename($0,".pl")." $execute_crt_tstmp  $$ ======================\n";		
	
	my %current_list;
	
	
	# watchdog
	my $filename_wdg = 'wdg_macd.txt';
	open(my $fh_wdg, '>', $filename_wdg) or die "Could not open file '$filename_wdg' $!";
	print $fh_wdg "$execute_crt_tstmp\n";
	close $fh_wdg;	
	
	my $buy_next = "WRONG";


	#do the sampling
	%current_list = get_pair_list();
	
	# print Dumper \%current_list;
	
	
	##alina timeDiff
	my $crtTime =   Time::Piece->strptime($execute_crt_tstmp,'%Y-%m-%d_%H-%M-%S');	
	my $minute = 0;
	my $reminder = 0;
	my $endMinute	= 0;
	my $endTfTime = 0;
	{
	  use integer;
	  $minute = $crtTime->strftime("%M");
	  $reminder = $minute % $sample_minutes;
	  $reminder = $sample_minutes - $reminder;
	  $minute += $reminder;
	  if ( $minute == 60 )
	  {
		$minute = 59;
		$endMinute = sprintf("%02s",$minute);
		$endTfTime = $crtTime->strftime("%Y-%m-%d_%H-$endMinute-59");
	  }
		else
		{
		$endMinute = sprintf("%02s",$minute);
		$endTfTime = $crtTime->strftime("%Y-%m-%d_%H-$endMinute-00");
		}
	}
	$endTfTime = Time::Piece->strptime($endTfTime,'%Y-%m-%d_%H-%M-%S');	
	
	print "$execute_crt_tstmp $endTfTime ".( $endTfTime - $crtTime )."\n";
	if  (( ( $endTfTime - $crtTime ) < 25 ) && ( $runOnce == 0 ) )
	{
		print "the end of the timeslot is near \n";
		print " =========  get next buy ticker ".timestamp()." \n";
		$buy_next = get_next_buy_ticker($crt_pair,\%current_list);
		print " =========  end get next buy ticker ".timestamp()." \n";	
		$runOnce = 1;
	}
	
	if  ( ( $endTfTime - $crtTime ) > 50 )	
	{
		$runOnce = 0;
	}


	
	# sleep $sleep_interval;	
	# next;

	
	# get the state machine
	# my $execute_crt_tstmp = timestamp();
	# print "============================= poloniex trade $execute_crt_tstmp  $$ ======================\n";		
	my $state = get_state_machine();
	
	#switch for each state
	switch ($state) {
	case 1 { 
					print "BUYING $crt_pair \n";
					print "we stop this scripts now ! \n";
					exit 0;
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
							$buy_timeout++;
							#after 15 cycles cancel the order
							if ( $buy_timeout == 15 )
							{
								# cancel the order and go back to buying
								$polo_wrapper->cancel_order($crt_pair,$crt_order_number);
								#delete the last line from the status file
								open($filename_status_h,"+<$filename_status") or die;
									while (<$filename_status_h>) {
											if (eof($filename_status_h)) {
												 seek($filename_status_h,-(length($_)),2) or die;
												 truncate($filename_status_h,tell($filename_status_h)) or die;
											}
									}
								close $filename_status_h;
								
								#wait 20 seconds to cancel the order
								sleep 20;
							}
						}
					}
					else
					{
						# there is no order
						# print "there is no order \n";
						my $buy_ticker = $buy_next;
						if ( $buy_ticker ne "WRONG" )
						{
							print "buy now \n";
							# buy now
							# write status file - last line
							my $price = get_last($current_list{$buy_ticker});

							if ( $price > 0.00001000 )
							{
								$price = $price - 0.00000010;								
							}
							else
							{
								# just increase with the small resolution
								$price = $price - 0.00000001;							
							}
							my $buy_ammount = $btc_balance / $price ;
							# $buy_ammount = $buy_ammount - ($buy_ammount * 0.0015);
							$current_spike++;
							print "amount to buy $buy_ammount $btc_balance $price \n";
							$buy_timeout = 0;
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
						print "$sell_ticker $latest_price ".get_tstmp($pairs_list{$sell_ticker})." delta_procent $procent $wining_procent\n";
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

										$latest_price = $latest_price + 0.00000010;								
									}
									else
									{
										# just decrease with the small resolution
										$latest_price = $latest_price + 0.00000001;							
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
					print "$current_spike $crt_tstmp BUYING $crt_pair 0 0 0 $btc_balance \n";
					open(my $filename_status_h, '>>', $filename_status) or warn "Could not open file '$filename_status' $!";
					print $filename_status_h "$current_spike $crt_tstmp BUYING $crt_pair 0 0 0 $btc_balance \n";
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

	# open(my $filename_samplings_all_h, '>>', $filename_samplings_all) or warn "Could not open file $filename_samplings_all $!";

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
						# print $filename_samplings_all_h "$tstmp $coinName $percentChange $low24hr $last $high24hr $lowestAsk $quoteVolume $baseVolume $id $highestBid $isFrozen \n";
						# push @current_list, %elem_hash;				
					}
				}
			}
		}
	}
	# close $filename_samplings_all_h;				
				# push @current_list, @elem;	
	return %current_list;
}


sub get_next_buy_ticker
{
	my $func_tstmp = timestamp();

	my $funcTime = Time::Piece->strptime($func_tstmp,'%Y-%m-%d_%H-%M-%S');
	my $previous_ticker = shift;
	my $current_sample_list = shift;
	
	$previous_ticker = "BTC_$previous_ticker";

	# print Dumper $current_sample_list;
	
	
	my $buy_next_ticker = "WRONG";

	# print Dumper @queue_pairs_lists;
	foreach (sort (keys ($current_sample_list)))
	{
		my $ticker = $_;
		
		my $compose_file = "macd/".$ticker."_".$filename_macd;
		open(my $filename_macd_h, '<', $compose_file) or warn "Could not open file $compose_file $!";
		my $last_line_macd = "";
		$last_line_macd = $_,while (<$filename_macd_h>);
		close $filename_macd_h;
		chomp($last_line_macd);		
		
		# if ( $previous_ticker eq $ticker )
		# {
			# don't try to buy the same ticker twice in a row
			# next;
		# }
		

		#macd
		my $previous_macd_crt = 0;
		my $previous_3day_crt	= 0;		
		my $previous_macd_price = 0;	
		my $previous_macd_tstmp = 0;
		my $previous_macd_26ema = 0;
		my $previous_macd_12ema = 0;
		my $previous_macd_9ema = 0;
		my $previous_macd = 0;
		my $previous_macd_5ema = 0;
		my $previous_macd_35ema = 0;
		my $previous_macd_5ema_signal = 0;
		my $previous_macd_signal = 0;		
		my $previous_macd_cross = 0;
		my $previous_macd_cross_direction = 0;
		my $previous_macd_zero = 0;
		
		# 3 day tren
		my $previous_3day_12ema = 0;
		my $previous_3day_26ema = 0;
		my $previous_3day_9ema = 0;		
		my $previous_3day_macd = 0;		
		
		
		
		my $restart_ema = 0;
		
	
		if ( $last_line_macd =~ /^$/ )
		{
			print "$compose_file is empty !!\n";						
			$restart_ema = 1;
		}
		else
		{
			# print "$compose_file is not empty \n";
			# tstmp 26ema 12ema 9ema macd macdcross macdcroos_direction macd_zero
			# print "[$last_line_macd]\n";
			if ( $last_line_macd =~ /(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+/ )
			{
				$previous_macd_crt = $1;			
				$previous_macd_price = $3;
				$previous_macd_tstmp = $2;
				$previous_macd_26ema = $4;
				$previous_macd_12ema = $5;
				$previous_macd_9ema = $6;
				$previous_macd = $7;
				$previous_macd_cross = $8;
				$previous_macd_cross_direction = $9;
				$previous_macd_zero = $10;
				$previous_macd_5ema = $11;
				$previous_macd_35ema = $12;
				$previous_macd_5ema_signal = $13;
				$previous_macd_signal = $14;					
				
				$previous_3day_12ema = $15;
				$previous_3day_26ema = $16;
				$previous_3day_9ema = $17;		
				$previous_3day_macd = $18;						
				$previous_3day_crt = $19;				
				
				
				my $previousMacdTime = Time::Piece->strptime($previous_macd_tstmp,'%Y-%m-%d_%H-%M-%S');
				
				my $last_tstmp = get_tstmp($current_sample_list->{$ticker});
				my $lastTime = Time::Piece->strptime($last_tstmp,'%Y-%m-%d_%H-%M-%S');
				
				print "$last_tstmp  -  $previous_macd_tstmp \n";

				# if is more then 15 minutes we need to restart the macd calculus
				if ( ($lastTime - $previousMacdTime) > $max_distance)
				{
					print "the time distance between the first and last sample is to high ".($lastTime - $previousMacdTime)."  $max_distance \n";
					$restart_ema = 1;
				}
				
				if  (  ($lastTime - $previousMacdTime) < $min_distance )
				{
					print "distance from the last to previous is to small ".($lastTime - $previousMacdTime)." $min_distance\n";
					$restart_ema = 1;
				}
				
				
				# print "READ last $previous_macd_crt $previous_macd $previous_macd_26ema $previous_macd_12ema $func_tstmp  $previous_macd_tstmp ".($funcTime - $previousMacdTime)."\n";
			}
		}

		my $crt_crt = 1;
		
		my $current_price = get_last($current_sample_list->{$ticker});		
		my $crt_26ema =  $current_price;
		my $crt_12ema =  0;
		my $crt_9ema =  0;
		my $crt_macd = 0;
		my $crt_35ema =  $current_price;
		my $crt_5ema =  0;
		my $crt_5ema_signal =  0;
		my $crt_macd_signal = 0;
		
		my $crt_macd_cross = 0;
		my $crt_macd_cross_direction = 0;
		my $crt_macd_zero = 0;
		
		

		my $crt_3day_12ema = 0;
		my $crt_3day_26ema = 0;
		my $crt_3day_9ema = 0;
		my $crt_3day_macd = 0;		
		my $crt_3day_crt = 1;

		

		if ( $restart_ema == 1 )
		{
			print "restart ema \n";
			# print "$crt_crt $func_tstmp $current_price ".sprintf("%0.08f",$crt_26ema)." ".sprintf("%0.08f",$crt_12ema)." ".sprintf("%0.08f",$crt_9ema)." ".sprintf("%0.08f",$crt_macd)." ".sprintf("%0.08f",$crt_macd_cross)." ".sprintf("%0.08f",$crt_macd_cross_direction)." ".sprintf("%0.08f",$crt_macd_zero)." \n";		
			open(my $filename_macd_h, '>', $compose_file) or warn "Could not open file $compose_file $!";
			print $filename_macd_h "$crt_crt $func_tstmp $current_price ".sprintf("%0.08f",$crt_26ema)." ".sprintf("%0.08f",$crt_12ema)." ".sprintf("%0.08f",$crt_9ema)." ".sprintf("%0.08f",$crt_macd)." ".sprintf("%0.08f",$crt_macd_cross)." ".sprintf("%0.08f",$crt_macd_cross_direction)." ".sprintf("%0.08f",$crt_macd_zero)." ".sprintf("%0.08f",$crt_5ema)." ".sprintf("%0.08f",$crt_35ema)." ".sprintf("%0.08f",$crt_5ema_signal)." ".sprintf("%0.08f",$crt_macd_signal)." ".sprintf("%0.08f",$crt_3day_12ema)." ".sprintf("%0.08f",$crt_3day_26ema)." ".sprintf("%0.08f",$crt_3day_9ema)." ".sprintf("%0.08f",$crt_3day_macd)." ".sprintf("%0.08f",$crt_3day_crt)." \n";
			close $filename_macd_h;

		} # restart ema
		else
		{
			print "calculate normal \n";
			my $multiplier_26 = 2/(26+1);
			my $multiplier_12 = 2/(12+1);
			my $multiplier_9 = 2/(9+1);		

			my $multiplier_35 = 2/(35+1);
			my $multiplier_5 = 2/(5+1);

			
			if (( $previous_macd_crt > 13 ) && ( $previous_macd_crt < 25 ))
			{
				$crt_12ema += $previous_macd_12ema + $current_price ;
			}
			if ( $previous_macd_crt == 25 )
			{
				$crt_12ema += $previous_macd_12ema + $current_price ;			
				$crt_12ema = $crt_12ema / 12;
			}
			if ( $previous_macd_crt > 25 )
			{
				$crt_12ema = (($current_price - $previous_macd_12ema) * $multiplier_12) + $previous_macd_12ema;			
			}
			
			if ( $previous_macd_crt < 25 )
			{
				$crt_26ema += $previous_macd_26ema;
			}
			if ( $previous_macd_crt == 25 )
			{
				$crt_26ema += $previous_macd_26ema;			
				$crt_26ema = $crt_26ema / 26;
			}
			if ( $previous_macd_crt > 25 )
			{
				$crt_26ema = (($current_price - $previous_macd_26ema) * $multiplier_26) + $previous_macd_26ema;			
			}
			

			if ($previous_macd_crt > 25)
			{
				$crt_macd =  $crt_12ema - $crt_26ema;
			}
			if (($previous_macd_crt > 25) && ($previous_macd_crt < 34))
			{
				$crt_9ema += $crt_macd + $previous_macd_9ema;				
			}
			if ($previous_macd_crt == 34)
			{
				$crt_9ema += $crt_macd + $previous_macd_9ema;	
				$crt_9ema = $crt_9ema / 9;
			}
			if ($previous_macd_crt > 34)
			{
				$crt_9ema = (($crt_macd - $previous_macd_9ema) * $multiplier_9) + $previous_macd_9ema;						
			}
			
			
			# 5 35 5
			
			if (( $previous_macd_crt > 29 ) && ( $previous_macd_crt < 34 ))
			{
				$crt_5ema += $previous_macd_5ema + $current_price ;
			}
			if ( $previous_macd_crt == 34 )
			{
				$crt_5ema += $previous_macd_5ema + $current_price ;			
				$crt_5ema = $crt_5ema / 5;
			}
			if ( $previous_macd_crt > 34 )
			{
				$crt_5ema = (($current_price - $previous_macd_5ema) * $multiplier_5) + $previous_macd_5ema;			
			}
			
			
			if ( $previous_macd_crt < 34 )
			{
				$crt_35ema += $previous_macd_35ema;
			}
			if ( $previous_macd_crt == 34 )
			{
				$crt_35ema += $previous_macd_35ema;			
				$crt_35ema = $crt_35ema / 35;
			}
			if ( $previous_macd_crt > 34 )
			{
				$crt_35ema = (($current_price - $previous_macd_35ema) * $multiplier_35) + $previous_macd_35ema;			
			}
			

			if ($previous_macd_crt > 34)
			{
				$crt_macd_signal =  $crt_5ema - $crt_35ema;
			}
			
			if (($previous_macd_crt > 34) && ($previous_macd_crt < 39))
			{
				$crt_5ema_signal += $crt_macd_signal + $previous_macd_5ema_signal;				
			}
			if ($previous_macd_crt == 39)
			{
				$crt_5ema_signal += $crt_macd_signal + $previous_macd_5ema_signal;	
				$crt_5ema_signal = $crt_5ema_signal / 5;
			}
			if ($previous_macd_crt > 39)
			{
				$crt_5ema_signal = (($crt_macd_signal - $previous_macd_5ema_signal) * $multiplier_5) + $previous_macd_5ema_signal;						
			}
						
			$crt_crt = $previous_macd_crt + 1;
			
			
			
			# make the 3 days trend detection
			# one sample every 3 hours
			#alina timeDiff
			my $now =  timestamp();
			my $crtTime =   Time::Piece->strptime($now,'%Y-%m-%d_%H-%M-%S');	
			my $hour = 0;
			my $reminder = 0;
			my $endhour	= 0;
			my $endTfTime = 0;
			{
				use integer;
				$hour = $crtTime->strftime("%H");
				$reminder = $hour % (3);
				$reminder = (3) - $reminder;
				$hour += $reminder;
				if ( $hour == 24 )
				{
				$hour = 23;
				$endhour = sprintf("%02s",$hour);
				$endTfTime = $crtTime->strftime("%Y-%m-%d_$hour-59-59");
				}
				else
				{
				$endhour = sprintf("%02s",$hour);
				$endTfTime = $crtTime->strftime("%Y-%m-%d_$hour-00-00");
				}
			}
			$endTfTime = Time::Piece->strptime($endTfTime,'%Y-%m-%d_%H-%M-%S');	
			
			print "3 day trend $now $endTfTime ".( $endTfTime - $crtTime )."\n";
			if  (( ( $endTfTime - $crtTime ) < 90 ) && ( $runOnce_3day == 0 ) )
			{
				print "the end of the timeslot is near \n";
				print " =========  3day trend ".timestamp()." \n";

				print "calculate normal \n";
				my $multiplier_26 = 2/(26+1);
				my $multiplier_12 = 2/(12+1);
				my $multiplier_9 = 2/(9+1);		

				my $multiplier_35 = 2/(35+1);
				my $multiplier_5 = 2/(5+1);

				
				if (( $previous_3day_crt > 13 ) && ( $previous_3day_crt < 25 ))
				{
					$crt_3day_12ema += $previous_3day_12ema + $current_price ;
				}
				if ( $previous_3day_crt == 25 )
				{
					$crt_3day_12ema += $previous_3day_12ema + $current_price ;			
					$crt_3day_12ema = $crt_3day_12ema / 12;
				}
				if ( $previous_3day_crt > 25 )
				{
					$crt_3day_12ema = (($current_price - $previous_3day_12ema) * $multiplier_12) + $previous_3day_12ema;			
				}
				
				if ( $previous_3day_crt < 25 )
				{
					$crt_3day_26ema += $previous_3day_26ema;
				}
				if ( $previous_3day_crt == 25 )
				{
					$crt_3day_26ema += $previous_3day_26ema;			
					$crt_3day_26ema = $crt_3day_26ema / 26;
				}
				if ( $previous_3day_crt > 25 )
				{
					$crt_3day_26ema = (($current_price - $previous_3day_26ema) * $multiplier_26) + $previous_3day_26ema;			
				}
				

				if ($previous_3day_crt > 25)
				{
					$crt_3day_macd =  $crt_3day_12ema - $crt_3day_26ema;
				}
				if (($previous_3day_crt > 25) && ($previous_3day_crt < 34))
				{
					$crt_3day_9ema += $crt_3day_macd + $previous_3day_9ema;				
				}
				if ($previous_3day_crt == 34)
				{
					$crt_3day_9ema += $crt_3day_macd + $previous_3day_9ema;	
					$crt_3day_9ema = $crt_3day_9ema / 9;
				}
				if ($previous_3day_crt > 34)
				{
					$crt_3day_9ema = (($crt_3day_macd - $previous_3day_9ema) * $multiplier_9) + $previous_3day_9ema;						
				}			
				
				$crt_3day_crt = $previous_3day_crt + 1;			
				
				print " =========  end 3day trend ".timestamp()." \n";	
				$runOnce_3day = 1;
			}
			else
			{
				$crt_3day_12ema	=	$previous_3day_12ema;
				$crt_3day_26ema	=	$previous_3day_26ema;
				$crt_3day_9ema = $previous_3day_9ema;
				$crt_3day_macd = $previous_3day_macd;				
				$crt_3day_crt = $previous_3day_crt;					
			}
			
			if  ( ( $endTfTime - $crtTime ) > 50 )	
			{
				$runOnce_3day = 0;
			}
			#########################################			
				
				
			
			
			
			
			
			# print "WRITING last $crt_crt $previous_macd_crt\n";
			# print "$crt_crt $func_tstmp $current_price ".sprintf("%0.08f",$crt_26ema)." ".sprintf("%0.08f",$crt_12ema)." ".sprintf("%0.08f",$crt_9ema)." ".sprintf("%0.08f",$crt_macd)." ".sprintf("%0.08f",$crt_macd_cross)." ".sprintf("%0.08f",$crt_macd_cross_direction)." ".sprintf("%0.08f",$crt_macd_zero)." \n";
			open(my $filename_macd_h, '>>', $compose_file) or warn "Could not open file $compose_file $!";
			print $filename_macd_h "$crt_crt $func_tstmp $current_price ".sprintf("%0.08f",$crt_26ema)." ".sprintf("%0.08f",$crt_12ema)." ".sprintf("%0.08f",$crt_9ema)." ".sprintf("%0.08f",$crt_macd)." ".sprintf("%0.08f",$crt_macd_cross)." ".sprintf("%0.08f",$crt_macd_cross_direction)." ".sprintf("%0.08f",$crt_macd_zero)." ".sprintf("%0.08f",$crt_5ema)." ".sprintf("%0.08f",$crt_35ema)." ".sprintf("%0.08f",$crt_5ema_signal)." ".sprintf("%0.08f",$crt_macd_signal)." ".sprintf("%0.08f",$crt_3day_12ema)." ".sprintf("%0.08f",$crt_3day_26ema)." ".sprintf("%0.08f",$crt_3day_9ema)." ".sprintf("%0.08f",$crt_3day_macd)." ".sprintf("%0.08f",$crt_3day_crt)." \n";
			close $filename_macd_h;
			
		}
		
		# print "$ticker $crt_crt $current_price ".sprintf("%0.08f",$crt_9ema)." ".sprintf("%0.08f",$crt_macd)." ".sprintf("%0.08f",$previous_macd_9ema)." ".sprintf("%0.08f",$previous_macd)." \n";
		print "$ticker $crt_crt $current_price \n";
		
		

		
		
		
		
		# buy only if we have enough samples to make a decision
		if ( $crt_crt > 52 )
		{
			if ( $previous_macd < $previous_macd_9ema )
			{
				if ( $crt_macd > $crt_9ema )
				{
					# we have a cros from low to high of macd
					#we should buy now
					$buy_next_ticker = $ticker;
				}
			}
		}
		
		
		
		
		
		
		
	} # end of foreach
	
	# return "WRONG";
	
	if ( $buy_next_ticker eq "WRONG" )
	{
		print "There is no good ticker $buy_next_ticker!\n";
	}
	else
	{
		print "the next to buy  ticker is $buy_next_ticker \n";	
	}
	return $buy_next_ticker;

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


sub test()
{
			# make the 3 days trend detection
			# one sample every 3 hours
			#alina timeDiff
			my $now =  timestamp();
			my $crtTime =   Time::Piece->strptime($now,'%Y-%m-%d_%H-%M-%S');	
			my $ora = 0;
			my $reminder = 0;
			my $endhour	= 0;
			my $endTfTime = 0;
			{
				use integer;
				$ora = $crtTime->strftime("%H");
				print "$ora \n";
				$reminder = $ora % (3);
				$reminder = (3) - $reminder;
				$ora += $reminder;
				if ( $ora == 24 )
				{
				$ora = 23;
				$endhour = sprintf("%02s",$ora);
				$endTfTime = $crtTime->strftime("%Y-%m-%d_$ora-59-59");
				}
				else
				{
				$endhour = sprintf("%02s",$ora);
				$endTfTime = $crtTime->strftime("%Y-%m-%d_$ora-00-00");
				}
			}
			
			print "$endTfTime\n";
			
			 $endTfTime = Time::Piece->strptime($endTfTime,'%Y-%m-%d_%H-%M-%S');	
			
}