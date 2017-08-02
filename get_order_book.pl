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

my @samplings = ();
my $samplings_lists_size = 6; #size of the list with all samplings
my $hashref_temp = 0;

my $previous_price = 0;
my $has_pending_order = 0; # bit to see if there is a pending order ot not
my $crt_order_number = 0; # in case there is a pending order, this should express the order number
my $crt_pair = 0; # the current pair in the order
my $crt_tstmp = 0; # the tstmp of the current order
my $crt_price = 0; # the current price in the order
my $crt_amount = 0; # the current amount in the order
my $current_spike = 0; # the current number of buy/sell 
my $btc_balance = 0.001; # the amount in BTC
my @queue_pairs_lists; # list with all samplings
my $queue_pairs_lists_size = 5; # size of the list with all samplings
my $wining_procent = 1.5; # the procent where we sell
my $wining_procent_divided = $wining_procent / 100; # the procent where we sell
my $down_delta_procent_threshold =  0.5; # the procent from max win down
my $filename_status= "poloniex_status.ctrl";
my $filename_status_h;

my $filename_selling= "poloniex_selling.ctrl";
my $filename_selling_h;


my $filename_samplings= "get_order_book_samplings.ctrl";
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
sub gm_timestamp;
sub trim;
sub get_state_machine;
sub get_pair_list;
sub get_next_buy_ticker;
sub get_order_trade_tick;

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


my $start_chunk = 0;
open $filename_samplings_h, $filename_samplings or warn "Could not open $filename_samplings: $!";

my $chunk_array;
my $chunk_index = 0;
my $previous_pair="";
my %coinData_read;
my $sells_index = 0;
my @sells_read = ();
my $buys_index = 0;
my @buys_read = ();
my $trades_index = 0;
my @trades_read = ();
my $pairs_read;

my $pair = "";
while( my $line = <$filename_samplings_h>)  {   
	chomp($line);

	if ( $start_chunk == 1 )
	{
		if ( $line =~ /.*STOP.*/ )
		{
			#stop
			$start_chunk = 0;
			$chunk_index++;
			$sells_index = 0;
			$buys_index = 0;	
			$trades_index = 0;			
			# print Dumper $chunk_array;
			push @samplings , $chunk_array;
			
		}
		else
		{
			if ( $previous_pair eq "" )
				{
					$previous_pair = $pair;
				}
			# every line here is good
			if ( $previous_pair ne $pair )
			{
				# we have a new pair

				
				$sells_index = 0;
				$buys_index = 0;	
				$trades_index = 0;
				
				$previous_pair = $pair;
			}
			# print "$line \n";
			if ( $line =~ /(\S*)\s+SELLS\s+(\S*?)\s+(\S*)/ )
			{
				$pair = $1;
				my $sell_price = $2;
				my $sell_amount = $3;
				
				$chunk_array->[$chunk_index]->{$pair}->{'sells'}->[$sells_index]->{'price'} = $sell_price;
				$chunk_array->[$chunk_index]->{$pair}->{'sells'}->[$sells_index]->{'amount'} = $sell_amount;				
				
				# print Dumper $sells_read[$sells_index];				
				$sells_index++;
				$buys_index = 0;	
				$trades_index = 0;

			}
			if ( $line =~ /(\S*)\s+BUYS\s+(\S*?)\s+(\S*)/ )			
			{
				$pair = $1;			
				my $buy_price = $2;
				my $buy_amount = $3;
				$chunk_array->[$chunk_index]->{$pair}->{'buys'}->[$buys_index]->{'price'} = $buy_price;
				$chunk_array->[$chunk_index]->{$pair}->{'buys'}->[$buys_index]->{'amount'} = $buy_amount;
				$sells_index = 0;
				$buys_index++;	
				$trades_index = 0;
			}
			if ( $line =~ /(\S*)\s+TRADES\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*)/ )			
			{
				$pair = $1;			
				my $trade_tstmp = $2;
				my $trade_tradeID = $3;
				my $trade_globalTradeID = $2;
				my $trade_type = $3;
				my $trade_amount = $2;
				my $trade_rate = $3;
				my $trade_total = $3;				

				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'tstmp'} = $trade_tstmp;
				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'tradeID'} = $trade_tradeID;
				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'globalTradeID'} = $trade_globalTradeID;
				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'type'} = $trade_type;
				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'amount'} = $trade_amount;
				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'rate'} = $trade_rate;
				$chunk_array->[$chunk_index]->{$pair}->{'trades'}->[$trades_index]->{'total'} = $trade_total;
				 # print Dumper $chunk_array->[$chunk_index]->{$pair}->[$trades_index];
				$sells_index = 0;
				$buys_index = 0;	
				$trades_index++;
			}
			

			# print "add to chunk \n";
			# print "$line \n";
			# # if ( $line =~ /(\S*?)\s+?(.*)$/ )
			# # {
				# print "[$1] [$2] \n";
				# $tmp_hash_chunk{$1} = $2;
			# }
		}
	}
	if ( $line =~ /.*START\s*(\S*?)/ )
	{
		#starts
		$start_chunk = 1;
		$sells_index = 0;
		$buys_index = 0;	
		$trades_index = 0;
		$pairs_read->{'tstmp'} = $1;
	}
}

close $filename_samplings_h;


# print Dumper @samplings;

# exit 0;


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
	 # print Dumper $decoded_json;
	
	print Dumper @samplings;
	# foreach (@samplings)
	# {
		# print "$_ \n";
	# }	
	
	# exit 0;
	get_order_trade_tick();
	
	
	
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

sub gm_timestamp {
   my $t = gmtime;
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
		$crt_amount = 0;
		$crt_tstmp = 0;
	}
	else
	{
		# extract state   crt tstmp state pair price amount ordernumber btc_balance
		if ( $last_line =~ /\s*?(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s+(\S*?)\s/ )
		{

			$current_spike = $1;
			$crt_tstmp = $2;
			$previous_state = $3;
			$crt_order_number = $7;
			$crt_pair = $4;
			$crt_price = $5;
			$crt_amount = $6;
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

sub get_order_trade_tick
{
	# get the state machine
	my %coinData;
	my $execute_crt_tstmp = timestamp();
	my $gm_crt_tstmp = gm_timestamp();

	$decoded_json=get_json("https://poloniex.com/public?command=returnOrderBook&currencyPair=ALL&depth=20");
	# print Dumper $decoded_json;
	foreach ( sort (keys( $decoded_json )) )
	{
		my $key = $_;
		my %orders;
		if ( $key =~ /BTC_.*/ )
		{
			# print "$_ $decoded_json->{$key}->{'isFrozen'} $decoded_json->{$key}->{'seq'}\n";

			if ( $decoded_json->{$key}->{'isFrozen'} == '0' )
			{
				# print "\tbids buy \n";			
				my @buys = ();
				my @sells = ();
				foreach (@{$decoded_json->{$key}->{'bids'}})
				{
				# print Dumper $_;				
					my %buy;
					# print "\t$_->[0] $_->[1] \n";
					$buy{'price'} = $_->[0];
					$buy{'amount'} = $_->[1];					
					push @buys , \%buy;
				}

				# print Dumper @buys;
				
				# print "\tasks sell \n";				
				foreach (@{$decoded_json->{$key}->{'asks'}})
				{
					my %sell;
					# print "\t$_->[0] $_->[1] \n";
					$sell{'price'} = $_->[0];
					$sell{'amount'} = $_->[1];					
					push @sells , \%sell;					
				}
				# print Dumper @sells;
				
				$orders{'buys'} = \@buys;
				$orders{'sells'} = \@sells;
				
				# print "first previous $crt_time_unix $previous_time_unix \n";
				# print "https://poloniex.com/public?command=returnTradeHistory&currencyPair=$key&start=$previous_time_unix&end=$crt_time_unix \n";
				# my $decoded2_json=get_json("https://poloniex.com/public?command=returnTradeHistory&currencyPair=$key&start=$previous_time_unix&end=$crt_time_unix");
				my $decoded2_json=get_json("https://poloniex.com/public?command=returnTradeHistory&currencyPair=$key");
				my @trades =();
				foreach (@{$decoded2_json})
				{
					my %trade;
					my $elem = $_;
					my $elem_tstmp = $elem->{'date'};
					$elem_tstmp =~ s/ /_/g;
					$elem_tstmp =~ s/:/-/g;
					# print "[$execute_crt_tstmp] [$elem_tstmp] \n";
					my $execute_crt_tstmp_Time = Time::Piece->strptime($execute_crt_tstmp,'%Y-%m-%d_%H-%M-%S');
					my $elem_tstmp_Time = Time::Piece->strptime($elem_tstmp,'%Y-%m-%d_%H-%M-%S');
					# print "Diff time ".($execute_crt_tstmp_Time - $elem_tstmp_Time)."\n";
					if  ( ( $execute_crt_tstmp_Time - $elem_tstmp_Time ) <  11000 )
					{
						# print "$elem_tstmp $elem->{'tradeID'} $elem->{'globalTradeID'} $elem->{'type'} $elem->{'amount'} $elem->{'rate'} $elem->{'total'}\n";					
						$trade{'tstmp'} = $elem_tstmp;
						$trade{'tradeID'} = $elem->{'tradeID'};
						$trade{'type'} = $elem->{'type'};
						$trade{'amount'} = $elem->{'amount'};
						$trade{'rate'} = $elem->{'rate'};
						$trade{'total'} = $elem->{'total'};
						$trade{'globalTradeID'} = $elem->{'globalTradeID'};
						push @trades , \%trade;
					}
				}
				$orders{'trades'} = \@trades;
				$coinData{$key} = \%orders;
				# print Dumper %orders;
			}
		}

	}
	$coinData{'tstmp'} = $execute_crt_tstmp;

	push @samplings , \%coinData;
	# print Dumper @samplings;
	if ($#samplings >= $samplings_lists_size )
	{
		shift @samplings;
	}
	
	open(my $filename_samplings_h, '>', $filename_samplings) or warn "Could not open file '$filename_samplings' $!";
	foreach (@samplings)
	{
		my $elem = \%$_;
		print $filename_samplings_h "START $elem->{'tstmp'} \n";
		foreach (sort (keys($elem)))
		{
			if ( $_ ne "tstmp" )
			{
				my $key = $_;
				foreach (@{$elem->{$key}->{'sells'}})
				{
					my $sell = \%$_;
					print $filename_samplings_h "$key SELLS $sell->{'price'} $sell->{'amount'} \n";
				}
				foreach (@{$elem->{$key}->{'buys'}})
				{
					my $buy = \%$_;
					print $filename_samplings_h "$key BUYS $buy->{'price'} $buy->{'amount'} \n";
				}
				foreach (@{$elem->{$key}->{'trades'}})
				{
					my $trades = \%$_;
					print $filename_samplings_h "$key TRADES $trades->{'tstmp'} $trades->{'tradeID'} $trades->{'globalTradeID'} $trades->{'type'} $trades->{'amount'} $trades->{'rate'} $trades->{'total'}\n";
				}			
			}
		}
		print $filename_samplings_h "STOP\n";
	}
	close $filename_samplings_h;	

}