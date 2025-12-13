#!/bin/bash
#This script is for making changes more quickly
while true; do
	vi setup.sh 
	echo ------------------------------------------------
	echo Should we abort changes? -----------------------
	echo ------------------------------------------------
	sleep 5
	echo ------------------------------------------------
	echo Making changes, please wait a couples of seconds
	echo ------------------------------------------------
	sed -i '/^SCRIPT_DATE=/c\SCRIPT_DATE='$(date +'%Y%m%d-%H%M') setup.sh 
       	git add . 
	git commit -m "$(date +'%Y%m%d-%H%M')" 
	git push
	grep ^SCRIPT_DATE setup.sh
	echo ------------------------------------------------
	echo Changes are done, Sleeping 10 seconds ----------
	echo ------------------------------------------------
	sleep 10
done
