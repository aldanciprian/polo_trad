#!/bin/sh

#. /home/ciprian/.bashrc
BASE=/media/sf_shared/temp/polo_trad/
pid=0
startup=0

ctrl_c()
{
	echo "GENESIS Trapped CTRL-C"
	if [ $pid -ne 0 ]
	then 
		#send a trap first
		kill -10 $pid 2>/dev/null
		sleep 10
		echo "Killing $pid"
		kill -9 $pid 2>/dev/null
		pid=0
	fi
	exit 0
}

trap ctrl_c INT

while [ 1 ]
do
	echo "============GENESIS polo trad $0  $$============"
	date
	cd $BASE/
	./manage_trade_macd.sh

	sleep 10s
done
