#!/bin/sh -x

while [ 1 ]
do
	PID_OUT=`ps -ef | grep poloniex_trade_market.pl | grep -v grep`
	# echo ${PID_OUT}
	if [ $? -eq 0 ]
	then
		#found one
		PID=`echo ${PID_OUT} | awk '{print $2}'`
		echo "balance pid is ${PID}"
	else
		./poloniex_trade_market.pl
		
	fi
	sleep 5s
done
