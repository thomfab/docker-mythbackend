#!/bin/bash

echo "Set correct timezone"
echo "TZ = $TZ"
if [[ $(cat /etc/timezone) != $TZ ]] ; then
  echo "Update timezone"
  echo "$TZ" > /etc/timezone
  exec  dpkg-reconfigure -f noninteractive tzdata
else
  echo "Timezone is already correct"
fi
