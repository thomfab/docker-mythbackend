#!/bin/bash

echo "Update mythtv user ids and groups"
echo "USER_ID=$USER_ID"
echo "GROUP_ID=$GROUP_ID"

USERID=${USER_ID:-99}
GROUPID=${GROUP_ID:-100}

echo "USERID=$USERID"
echo "GROUPID=$GROUPID"
groupmod -g $GROUPID users
usermod -u $USERID mythtv
usermod -g $GROUPID mythtv
usermod -d /home/mythtv mythtv
usermod -a -G mythtv,users,adm,sudo mythtv
chown -R mythtv:mythtv /home/mythtv/

# set permissions for files/folders
chown -R mythtv:users /var/lib/mythtv /var/log/mythtv
chown mythtv:users /mnt/recordings /mnt/video
