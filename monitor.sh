#!/usr/bin/env bash

if [ ! -f /ready-at-dawn-echo-arena/bin/win10/echovr.exe ]
then
	echo "The script was not able to find '/ready-at-dawn-echo-arena/bin/win10/echovr.exe', make sure the echo folder is properly set as a bind mount to '/ready-at-dawn-echo-arena' on the container"
	exit 22;
fi

ISMAINSERVRUNNING=0
DRYRUN=0
SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
SETTINGSFILE=$SCRIPTDIR/Ssettings.json
ISREGISTERED=0

# Checking if the first argument is set, if so apply the correct variable
if [ -z $1 ]
then
	if [[ $2 == "-d" ]]
	then
		DRYRUN=1;
	elif [[ $2 == "-s" ]]
	then
	waitForShutdown;
	fi
fi

# Changing directory to the script directory to do some initial set-up
cd $SCRIPTDIR
# Set-up wine on first boot as a workaround as doing it in the docker files seems to cause issues 
if [ ! -f .wine ]
then
	wineboot -i
	mkdir -p "/root/.wine/drive_c/users/root/AppData/Local/rad/echovr/users/dmo/"
	echo '{"legal":{"eula_version":1,"points_policy_version":1,"splash_screen_version":6,"game_admin_version":1},"social":{"group":"90DD4DB5-B5DD-4655-839E-FDBE5F4BC0BF"}}' > /root/.wine/drive_c/users/root/AppData/Local/rad/echovr/users/dmo/demoprofile.json
fi



# Checking if the Ssettings.json file is present, otherwise make it with default configs
if [ ! -f "$SETTINGSFILE" ]
then
	echo "Failed to find setting file, creating a new one from initial values...";
  	echo '{
		"Comment for the ErrorsToCheck array": "Array with the errors the server encounter that would need a restart. ### is used as a wildcard",
		"ErrorsToCheck": [
			"Unable to find MiniDumpWriteDump",
			"Ending multiplayer",
			"[TCP CLIENT] [R14NETCLIENT] connection to ### failed",
			"[WARNING] Dedicated: registration failed ###"
		],
		"LinesToExclude" :[
			"Ending multiplayer gameplay"
		],
		"ShutdownMessages":[
		"[ECHORELAY.GAMESERVER] Signaling end of session",
		"[NSLOBBY] registration successful",
		"[NETGAME] NetGame switching state (from logged in, to lobby)",
		"[TCP CLIENT] [R14NETCLIENT] connection to ### /config closed"
		],
		"RelayIP": "127.0.0.1:777"
		}' > Ssettings.json
fi

# Checking if the relay ip is valid in the Ssettings.json file, if not error out and exit
RELAYIP=$(jq -r '.RelayIP' "$SETTINGSFILE");
echo relayip = $RELAYIP
if [[ $RELAYIP == "" ]]
then
	echo "The relay ip could not be found in the setting file, make sure to set \"RelayIP\" to the ip of the Echo relay server in the config file.";
	exit 12;
fi

EchoArgs=$(jq -r '.EchoArgs' "$SETTINGSFILE");

# Function to take the messages array from the Ssettingsa.json and put it into a variable for use with the "grep" command
processMessages() {
TMPMES=""
OUTREGEX=""
while read MESS; do
TMPMES=$(echo "$MESS" | sed -e 's/###./\*.\*/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' )
if [[ $OUTREGEX == "" ]]
then
OUTREGEX=$TMPMES
fi
if [[ "$OUTREGEX" != "$TMPMES" ]]
then
OUTREGEX="${OUTREGEX}\|${TMPMES}"
fi
done <<< $(jq -r $1 $2)
echo "$OUTREGEX";
}

# Setting the various variable for the log output checks
SHUTDOWNREGEX=$(processMessages '.ShutdownMessages[]' "$SETTINGSFILE");
ERRORLINESTOEXCLUDE=$(processMessages '.LinesToExclude[]' "$SETTINGSFILE");
ERRORSREGEX=$(processMessages '.ErrorsToCheck[]' "$SETTINGSFILE");

# Changing directory to where the echo binaries should be
cd /ready-at-dawn-echo-arena/bin/win10

# Checking if dbgcore.dll exists and the sha1sum of the current dbgcore. Install the patch with `-noconsole` support if the sha1sum are not matching
if [ ! -f dbgcore.dll ] || [[ ! $(echo 87fd7388c52bc3ac22e8468b6823e19d1718266f\ \ dbgcore.dll | sha1sum -c -) ]]
then
	echo Updating the dbgcore.dll, saving the old one as dgbcore.dll.bkp
	if wget -q https://github.com/h4ck3r210/EchoRelay/releases/download/Patch/EchoRelay.Patch.dll
	then
		mv dbgcore.dll dbgcore.dll.bkp
		mv EchoRelay.Patch.dll dbgcore.dll
	else
		echo "Error downloading the new dll, skipping step..."
		echo "If the game fails to start, amke sure to review the "EchoArgs" in the sSettings.json file as some argument could be incompatible with the current patch version"
	fi
fi

# Simple function to launch echo
launchEcho()
{
	wine /ready-at-dawn-echo-arena/bin/win10/echovr.exe $EchoArgs > /root/tmplog 2>&1 &
	ECHOPID=$!
}

# Simple function to kill echo
stopEcho()
{
	kill -15 $ECHOPID
	ISREGISTERED=0
}

# Simple function to check if echo is currently running
function checkEchoRunningStatus()
{
    if [ -z $ECHOPID ]
    then
        false
    elif  pidof echovr.exe > /dev/null
    then
        true
    else
        false
    fi
}

# Function that will wait until the gameserver is empty before shuttting down
function waitForShutdown()
{
	while :
	do
	if checkEchoRunningStatus;
	then
		echo "Waiting for shutdown...";
		if tail -50 /root/tmplog  | grep "$SHUTDOWNREGEX";
		then
			echo "Server is empty, getting ready to shutdown...";
			sleep 5;
			stopEcho;
			exit 0;
		fi
	else
	echo "Gameserver service not running, exiting...";
	exit 0;
	fi
	sleep 10;
	done
}

function checkMainServerConnectionLoop()
{
while [[ $ISMAINSERVRUNNING != 1 ]]
do
        echo "Entering loop to check connection with main server";
        curl -sSf http://$RELAYIP/api
	if [[ $? == 22 ]]
        then
                echo "Got connection to the main server";
                ISMAINSERVRUNNING=1
        	sleep 1
	else
	sleep 10;
	fi
done
}

# Trap SIGTERM and redirect it to the waitForShutdown function to wait for the server to be empty before closing
trap 'waitForShutdown' 15;


# Checking if the gameserver is already running, if not enter the checkMainServerConnectionLoop, then start the main program loop
echo "Checking if game server is already running";
if ! checkEchoRunningStatus;
then
	echo "Game server not running, checking connection to the main relay server before starting...";
	checkMainServerConnectionLoop;
	echo "Connection to relay server established, starting Game server...";
	if [[ $DRYRUN == 0 ]];then launchEcho;fi;
	sleep 1
else
	echo "Game server already running!"
fi
echo "Starting error check loop..."

# Main program loop that keeps checking the server status and auto restart if needed
while [[ $STOPEXEC != 1 ]]
do
	if checkEchoRunningStatus;
	then
		if [[ $ISREGISTERED == 0 ]] && [[ $(tail -10 /root/tmplog | grep "\[NSLOBBY\] Registered lobby *.*") ]]
		then
			ISREGISTERED=1
			tail -10 /root/tmplog | grep "\[NSLOBBY\] Registered lobby *.*"
		fi		
		tail -50 /root/tmplog | grep -v "$ERRORLINESTOEXCLUDE" | grep "$ERRORSREGEX"
		if tail -50 /root/tmplog | grep -v "$ERRORLINESTOEXCLUDE" | grep -q "$ERRORSREGEX";
		then
		echo "Server got a connection error, shutting it down and waiting a bit...";
		if [[ $DRYRUN == 0 ]];then stopEcho;fi;
		sleep 3;
		ISMAINSERVRUNNING=0;
		echo "Going back to check the status of the main server..."
		checkMainServerConnectionLoop;
		if [[ $ISMAINSERVRUNNING == 1 ]]
		then
			echo "Relay server back up, restarting game server...";
			if [[ $DRYRUN == 0 ]];then launchEcho;fi;
			sleep 1;
		fi
		fi
		sleep 10;
		else
			echo "Game server stopped, checking connection to relay then attempting to restart it..."
			checkMainServerConnectionLoop;
			if [[ $DRYRUN == 0 ]];then launchEcho;fi;
			sleep 5
	fi
done