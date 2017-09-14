#!/bin/bash

USERID=${USER_ID:-99}
GROUPID=${GROUP_ID:-100}
groupmod -g $GROUPID users
usermod -u $USERID mythtv
usermod -g $GROUPID mythtv
usermod -d /home/mythtv mythtv
usermod -a -G mythtv,users,adm,sudo mythtv
chown -R mythtv:mythtv /home/mythtv/

# set permissions for files/folders
chown -R mythtv:users /db /var/lib/mythtv /var/log/mythtv 
