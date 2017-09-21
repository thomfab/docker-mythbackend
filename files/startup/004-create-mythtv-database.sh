#!/bin/bash

#Does the MythTV Database Exist?
output=$(mysql -s -N -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'mythconverg'" information_schema)
  if [[ -z "${output}" ]]; then
echo "Creating database(s)."
  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} -e "CREATE DATABASE IF NOT EXISTS mythconverg"
  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} -e "CREATE USER 'mythtv' IDENTIFIED BY 'mythtv'"
  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} -e "GRANT ALL ON mythconverg.* TO 'mythtv' IDENTIFIED BY 'mythtv'"
  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} -e "GRANT CREATE TEMPORARY TABLES ON mythconverg.* TO 'mythtv' IDENTIFIED BY 'mythtv'"
  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${DATABASE_ROOT} -p${DATABASE_ROOT_PWD} -e "ALTER DATABASE mythconverg DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci"
fi

