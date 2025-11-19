#!/bin/bash
set -e

##### INSTRUCTION

# 1- Copier ce script dans le dossier a sauvegarder
# 2- Générez une paire de clés SSH dans un sous-dossier ./.ssh à côté de ce script
#    Exemple (à exécuter dans le même dossier que ce script):
#      mkdir -p ./.ssh && chmod 700 ./.ssh
#      ssh-keygen -t ed25519 -N '' -f ./.ssh/id_ed25519
# 3- Créer un nouveau dépot dans le borgwarehouse
#    - Ajoutez le contenu de ./.ssh/id_ed25519.pub
# 4- Initier le dépot via ce script (utilise la même clé SSH):
#      ./backup_folder_example.sh --init
# 5- Lancer le script sans option pour effectuer les backups et vérifier sur BWH
# 6- Créer une tâche cron aux intevalles que vous voulez avec les droits root ou pas au besoin
# ex : @daily bash /mnt/tank/nuage/backup.sh
#####



## Si vous voulez surveiller le script via sentry :
## Installez avec curl -sL https://sentry.io/get-cli/ | bash
## ou mettez a jour avec sentry-cli update
# export SENTRY_DSN=''
# eval "$(sentry-cli bash-hook)"


# CHANGE ME : absolute path du dossier à backuper
DUMPS_DIRECTORY="" 

mkdir -p $DUMPS_DIRECTORY

#### BORG SEND TO SSH ####

# CHANGE ME : le nom qui sera affiché au début de chaque backup. ex : nextcloud_de_moi
PREFIX=""

DATE_NOW=$(date +%Y-%m-%d-%H-%M) # on rajoute au PREFIX la date

# CHANGE ME : l'adresse du dépot, la même que celle lors de la création du dépot borg
# ex : ssh://borgwarehouse@localhost:2226/./674b31c6
export BORG_REPO="" 

# CHANGE ME : le pass généré lors de la création du dépot borg
export BORG_PASSPHRASE="" 

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes 
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

## Clé SSH locale au dossier: utilise automatiquement ./.ssh/id_ed25519 à côté du script
# Cela permet à `borg create` et `borg prune` d'utiliser la même clé via BORG_RSH
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
LOCAL_SSH_DIR="$SCRIPT_DIR/.ssh"
IDENTITY_FILE="$LOCAL_SSH_DIR/id_ed25519"

if [ -f "$IDENTITY_FILE" ]; then
  chmod 600 "$IDENTITY_FILE" 2>/dev/null || true
  export BORG_RSH="/usr/bin/ssh -oStrictHostKeyChecking=accept-new -oIdentitiesOnly=yes -i $IDENTITY_FILE"
else
  echo "[INFO] Aucune clé trouvée à $IDENTITY_FILE. SSH utilisera la configuration système par défaut (agent/ssh_config)." >&2
fi

# Mode init: si appelé avec --init, on initialise le dépôt puis on sort
if [ "${1:-}" = "--init" ]; then
  echo "$DATE_NOW initialisation du dépôt borg ($BORG_REPO) avec chiffrement repokey-blake2"
  /usr/bin/borg init -e repokey-blake2 "$BORG_REPO"
  exit 0
fi

echo $DATE_NOW" on cree l'archive borg "
/usr/bin/borg create -vs --compression lz4 \
  $BORG_REPO::$PREFIX-$DATE_NOW \
  $DUMPS_DIRECTORY


echo $DATE_NOW" on prune les vieux borg :"
/usr/bin/borg prune -v --list --keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1 --keep-yearly=-1 $BORG_REPO
