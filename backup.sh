#!/usr/bin/env bash

if [ `id -u` -ne 0 ]
  then echo "Please run as root"
  exit
fi

set -o nounset
set -o pipefail

readonly SOURCE_PATHS="/home/dokku /var/lib/dokku/config /var/lib/dokku/data /var/lib/dokku/services /var/lib/dokku/plugins"
readonly BACKUP_DIR="/mnt/backups"
readonly DATETIME="$(date '+%Y-%m-%d_%H:%M:%S')"
readonly BACKUP_PATH="${BACKUP_DIR}/${DATETIME}"
readonly LATEST_LINK="${BACKUP_DIR}/latest"

readonly KEEP_BACKUPS_DAYS=7

export DOKKU_QUIET_OUTPUT=true

cleanup_failure () {
  echo "Backup failed -- removing incomplete backup ${BACKUP_PATH}"
  rm -rf $BACKUP_PATH
  exit 1
}

trap 'cleanup_failure' ERR INT TERM

mkdir -p /var/lib/dokku/services
chown dokku:dokku /var/lib/dokku/services

backup_config () {
  mkdir -p $BACKUP_DIR
  rsync -aRhv --delete --protect-args \
    --link-dest $LATEST_LINK \
    $SOURCE_PATHS \
    $BACKUP_PATH
}

backup_all_postgres () {
  mkdir -p "${BACKUP_PATH}/postgres/"
  for db in $(dokku postgres:list); do
    dokku postgres:export $db > "${BACKUP_PATH}/postgres/${db}.sql"
  done
}

backup_all_redis () {
  mkdir -p "${BACKUP_PATH}/redis/"
  for db in $(dokku redis:list); do
    dokku redis:export $db > "${BACKUP_PATH}/redis/${db}.sql"
  done
}

prune_old_backups () {
  find $BACKUP_DIR -maxdepth 1 -type d -mtime "+${KEEP_BACKUPS_DAYS}" | xargs -0 -I{} sh -c 'echo "Pruning old backup {}"; rm -rf {}'
}

set -x

prune_old_backups
backup_config
backup_all_postgres
backup_all_redis

# set the latest link to the new backup
ln -snf "${BACKUP_PATH}" "${LATEST_LINK}"
