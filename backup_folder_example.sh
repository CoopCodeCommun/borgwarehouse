#!/bin/bash
set -e

## Si vous voulez surveiller le script via sentry :
## Installez avec curl -sL https://sentry.io/get-cli/ | bash
## ou mettez a jour avec sentry-cli update
# export SENTRY_DSN=''
# eval "$(sentry-cli bash-hook)"


DUMPS_DIRECTORY="" # CHANGE ME : absolute path du dossier à backuper
mkdir -p $DUMPS_DIRECTORY

#### BORG SEND TO SSH ####
PREFIX="nuagemietefr" # CHANGE ME : le nom qui sera affiché au début de chaque backup
DATE_NOW=$(date +%Y-%m-%d-%H-%M) # on rajoute au PREFIX la date

export BORG_REPO="" # CHANGE ME : l'adresse du dépot, la même que celle lors de la création du dépot borg
export BORG_PASSPHRASE="" # CHANGE ME : le pass généré lors de la création du dépot borg
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes 
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

echo $DATE_NOW" on cree l'archive borg "
/usr/bin/borg create -vs --compression lz4 \
  $BORG_REPO::$PREFIX-$DATE_NOW \
  $DUMPS_DIRECTORY


echo $DATE_NOW" on prune les vieux borg :"
/usr/bin/borg prune -v --list --keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1 --keep-yearly=-1 $BORG_REPO
