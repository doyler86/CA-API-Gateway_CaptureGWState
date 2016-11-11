#!/bin/bash
#
# Script to capture pertinent details from a gateway for troubleshooting
#
# Runs vmstat for 30 seconds in the background
# Runs top for 10 seconds after vmstat has run for 10 seconds
# Wait 3 more seconds then captures other metrics
# Waits for all process to finish then bundles up in a zip file to ~ssgconfig
#
# Revision History: 
# ~~~~~~~~~~~~~~~~~
# Jay MacDonald - v1 - 20160803
# Jay MacDonald - v2 - 20160831 - Switched to concurrent capture
# Doyle Reece   - v3 - 20161107 - Added node.properties and system.properties

OPTS="hH"

GET_HEAP="no"

print_help () {
	echo "$0 - capture troubleshooting details from a Gateway"
	echo ""
	echo "Command line parameters:"
	echo "  -H	: Capture heap dump (intrusive)"
	echo "  -h	: Print this list and exit"
        echo ""
}

while getopts $OPTS opt ; do
	case $opt in
	   h)	print_help
		exit 0
		;;

	   H)   GET_HEAP="yes"
		;;
	esac
done

TSTAMP=$(date +%F:%T)
mkdir $TSTAMP
echo -n "=> Starting 30 second vmstat capture: "
vmstat -tn 1 30 > $TSTAMP/vmstat-$HOSTNAME &
echo "OK ($!)"
PIDLIST=$!

echo -n "-> Waiting 10 seconds to start top"
for i in {1..10} ; do echo -n . ; sleep 1 ; done ; echo ''

echo -n "=> Starting top capture (threads): "
top -d 1 -n 10 -bH > $TSTAMP/top_threads_output-$HOSTNAME &
echo "OK ($!)"
PIDLIST="$PIDLIST $!"

echo -n "=> Starting top capture (no threads): "
top -d 1 -n 10 -b > $TSTAMP/top_nothreads_output-$HOSTNAME &
echo "OK ($!)"
PIDLIST="$PIDLIST $!"

echo -n "-> Waiting 3 seconds to start state captures"
for i in {1..3} ; do echo -n . ; sleep 1 ; done ; echo ''

echo -n "=> Capturing process tree: "
ps afuxwww > $TSTAMP/ps_forest-$HOSTNAME &
echo "OK ($!)"
PIDLIST="$PIDLIST $!"

echo -n "=> Capturing network stats: "
netstat -tnap  > $TSTAMP/netstat-$HOSTNAME &
echo "OK ($!)"
PIDLIST="$PIDLIST $!"

echo -n "=> Capturing memory stats: "
free -m > $TSTAMP/free-$HOSTNAME &
echo "OK ($!)"
PIDLIST="$PIDLIST $!"

GWPID=$(ps awwx | grep Gateway.jar | grep -v grep | awk '{print $1}')

echo -n "=> Starting thread dump for PID=$GWPID: "
su gateway -c "/opt/SecureSpan/JDK/bin/jstack $GWPID > /tmp/gw_thread_dump-$HOSTNAME" &
echo "OK ($!)"
PIDLIST="$PIDLIST $!"

if [ "$GET_HEAP" == "yes" ] ; then
	echo -n "=> Starting heap dump for PID=$GWPID: "
	su gateway -c "/opt/SecureSpan/JDK/bin/jmap -dump:live,format=b,file=/tmp/gw_heap_dump-$HOSTNAME $GWPID" &
	echo "OK ($!)"
	PIDLIST="$PIDLIST $!"
fi

echo "-> Waiting for all processes to complete:"

while [ "$PIDLIST" ] ; do
	NEWLIST=$PIDLIST
	echo "  -> WAITING on $NEWLIST"
	for PID in $PIDLIST ; do
		[ -d "/proc/$PID" ] || NEWLIST=$(echo $NEWLIST | sed "s/$PID *//")
	done
	PIDLIST=$NEWLIST
	sleep 5
done
echo "-> COMPLETE"

mv /tmp/gw_thread_dump-$HOSTNAME $TSTAMP

if [ "$GET_HEAP" == "yes" ] ; then
	mv /tmp/gw_heap_dump-$HOSTNAME $TSTAMP
fi

echo -n "=> Copying ssg log file: "
cp /opt/SecureSpan/Gateway/node/default/var/logs/ssg_0_0.log $TSTAMP/ssg_0_0.log-$HOSTNAME
echo "OK"

echo -n "=> Copying node.properties file: "
cp /opt/SecureSpan/Gateway/node/default/etc/conf/node.properties $TSTAMP/node.properties-$HOSTNAME
echo "OK"

echo -n "=> Copying system.properties file: "
cp /opt/SecureSpan/Gateway/node/default/etc/conf/system.properties $TSTAMP/system.properties-$HOSTNAME
echo "OK"

echo -n "=> Copying crontab for user: $USER "
crontab -l > $TSTAMP/crontab.output-$HOSTNAME
echo "OK"

echo "=> Generating zip file /home/ssgconfig/gw_state-$HOSTNAME-$TSTAMP.zip: "
zip -r /home/ssgconfig/gw_state-$HOSTNAME-$TSTAMP.zip $TSTAMP

if [ $? -eq 0 ] ; then
	echo "-> DONE"
	chown ssgconfig:ssgconfig /home/ssgconfig/gw_state-$HOSTNAME-$TSTAMP.zip $TSTAMP
else
	echo "  -> FAIL"
	exit 1
fi

echo -n "=> Removing working folder ($TSTAMP): "
rm -rf $TSTAMP
echo "OK"

echo ""

echo "==> Please download gw_state-$HOSTNAME-$TSTAMP.zip from"
echo "     /home/ssgconfig."
echo ""
