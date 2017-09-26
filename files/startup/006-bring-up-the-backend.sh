#!/bin/bash

chown -R mythtv:users /var/log/mythtv

echo "Checking whether database(s) are ready"
until [ "$( mysqladmin -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} status 2>&1 >/dev/null | grep -ci error:)" = "0" ]
do
echo "waiting....."
sleep 2s
done
echo "start backend"
exec /sbin/setuser mythtv /usr/bin/mythbackend --syslog local7 --daemon >/dev/null 2>&1 &
