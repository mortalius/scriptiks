#!/bin/bash

# Wrapper to automatically open new tab in terminator
# for telnet://ip:port style URIs in Firefox browser.

terminal="Terminator"
url="$1"
method=$(echo $url | sed -r -e "s/([a-z]+):.+/\1/")
ip=$(echo $url | sed -r -e "s/[a-z]+\:\/\/([.0-9]+)\:[0-9]+/\1/")
port=$(echo $url | sed -r -e "s/[a-z]+\:\/\/[.0-9]+\:([0-9]+)/\1/")

xdotool search --desktop 0 --class "$terminal" windowactivate --sync && xdotool key ctrl+shift+t

if [ "$method" == "telnet" ]; then
  sleep 1;
  xdotool type --delay 1 --clearmodifiers "telnet $ip $port"
  xdotool key Return
fi


