#!/bin/bash
mkdir -p /var/run/sshd
mkdir -p /root/.vnc

/usr/bin/supervisord -c /root/supervisor-files/rdp-supervisord.conf & >/dev/null 2>&1
