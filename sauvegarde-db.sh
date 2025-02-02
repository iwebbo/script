#!/bin/bash
# MYSQL config
DBHOST="127.0.0.1"
DBNAME="zabbix"
DBUSER="root"
DBPASS="pwd*"

# Utilitaires
MYSQLDUMP="`which mysqldump`"
GZIP="`which gzip`"
DATEBIN="`which date`"
MKDIRBIN="`which mkdir`"

# Path
MAINDIR="/etc/zabbix/script"
DUMPFILE="${MAINDIR}/zabbix_db_bck-`${DATEBIN} +%Y%m%d%H%M`"

# Dump Database Zabbix
${MYSQLDUMP} -h ${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBNAME} | ${GZIP} -9 > ${DUMPFILE}.sql.gz

echo
echo "Backup Completed - ${DUMPFILE}"

