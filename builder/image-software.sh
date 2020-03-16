#! /usr/bin/env bash

#
# Script for install software to the image.
#
# Copyright (C) 2020 Copter Express Technologies
#
# Author: Artem Smirnov <urpylka@gmail.com>
# Author: Andrey Dvornikov <dvornikov-aa@yandex.ru>
#

set -e # Exit immidiately on non-zero result

echo_stamp() {
  # TEMPLATE: echo_stamp <TEXT> <TYPE>
  # TYPE: SUCCESS, ERROR, INFO

  # More info there https://www.shellhacks.com/ru/bash-colors/

  TEXT="$(date '+[%Y-%m-%d %H:%M:%S]') $1"
  TEXT="\e[1m${TEXT}\e[0m" # BOLD

  case "$2" in
    SUCCESS)
    TEXT="\e[32m${TEXT}\e[0m";; # GREEN
    ERROR)
    TEXT="\e[31m${TEXT}\e[0m";; # RED
    *)
    TEXT="\e[34m${TEXT}\e[0m";; # BLUE
  esac
  echo -e ${TEXT}
}

# https://gist.github.com/letmaik/caa0f6cc4375cbfcc1ff26bd4530c2a3
# https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/templates/header.sh
my_travis_retry() {
  local result=0
  local count=1
  while [ $count -le 3 ]; do
    [ $result -ne 0 ] && {
      echo -e "\n${ANSI_RED}The command \"$@\" failed. Retrying, $count of 3.${ANSI_RESET}\n" >&2
    }
    # ! { } ignores set -e, see https://stackoverflow.com/a/4073372
    ! { "$@"; result=$?; }
    [ $result -eq 0 ] && break
    count=$(($count + 1))
    sleep 1
  done

  [ $count -gt 3 ] && {
    echo -e "\n${ANSI_RED}The command \"$@\" failed 3 times.${ANSI_RESET}\n" >&2
  }

  return $result
}

echo_stamp "Update apt"
apt-get update
#&& apt upgrade -y

echo_stamp "Software installing"
apt-get install --no-install-recommends -y \
qt4-qmake \
qt4-dev-tools \
libqt4-dev-bin \
qt4-default \
tightvncserver \
xfonts-base \
&& echo_stamp "Everything was installed!" "SUCCESS" \
|| (echo_stamp "Some packages wasn't installed!" "ERROR"; exit 1)

echo_stamp "Build and install PixyMon"
cd /home/pi/pixymon-1.0.2beta \
&& ./buildpixymon.sh \
&& cp bin/PixyMon /usr/local/bin/ \
&& cp pixy.rules /etc/udev/rules.d/ \
&& cd .. \
&& rm -r "/home/pi/pixymon-1.0.2beta" \
&& echo_stamp "Pixymon was installed!" "SUCCESS" \
|| (echo_stamp "Failed to build and install PixyMon!" "ERROR"; exit 1)

echo_stamp "Configure VNC password"
echo "pixymon" | vncpasswd -f > /home/pi/.vnc/passwd

echo_stamp "Set drone role"
cp -f /home/pi/navtalink/wifibroadcast.cfg.drone /boot/wifibroadcast.txt \
&& systemctl enable wifibroadcast@drone \
&& systemctl enable navtalink-video \
&& systemctl enable mavlink-serial-bridge@drone \
&& systemctl enable mavlink-fast-switch@duocam-drone \
&& echo_stamp "Drone role was set!" "SUCCESS" \
|| (echo_stamp "Failed to set role!" "ERROR"; exit 1)

echo_stamp "Update VNC directory ownership and passwd permissions"
chown -R pi:pi /home/pi/.vnc \
&& chmod 0600 /home/pi/.vnc/passwd \
&& echo_stamp "VNC directory ownership and passwd permissions were updated!" "SUCCESS" \
|| (echo_stamp "Failed to update VNC directory ownership and passwd permissions!" "ERROR"; exit 1)

echo_stamp "End of software installation"
