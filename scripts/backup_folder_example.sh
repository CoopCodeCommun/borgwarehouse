#!/bin/bash
set -euo pipefail

##### INSTRUCTION
#
# Sauvegarde d'un DOSSIER complet vers un dépôt borgwarehouse (BWH).
#
# CONFIGURATION : ce script ne contient aucun secret. Il lit son .env, placé à
# côté de lui (voir env_example). Un script est fait pour être copié, versionné,
# partagé — une passphrase écrite dedans finit tôt ou tard dans un dépôt git.
#
# 1- Copier ce script dans (ou à côté du) dossier à sauvegarder.
# 2- Choisir un BORG_PREFIX, puis générer une paire de clés SSH DÉDIÉE à ce
#    dépôt dans ./.ssh (une clé = un dépôt, voir README) :
#      mkdir -p ./.ssh && chmod 700 ./.ssh
#      ssh-keygen -t ed25519 -N '' -f ./.ssh/nextcloud_ed25519   # nom = $BORG_PREFIX
# 3- Créer un nouveau dépôt dans borgwarehouse et y coller le contenu de
#    ./.ssh/nextcloud_ed25519.pub
# 4- Renseigner le .env :
#      cp env_example .env && chmod 600 .env
# 5- Initier le dépôt (utilise la même clé SSH) :
#      ./backup_folder_example.sh --init
# 6- Lancer sans option pour sauvegarder, puis vérifier sur BWH :
#      ./backup_folder_example.sh
# 7- Créer une tâche cron aux intervalles voulus (droits root ou non au besoin) :
#      @daily bash /chemin/vers/backup_folder_example.sh
#####

## Surveillance optionnelle via Sentry :
## Installez : curl -sL https://sentry.io/get-cli/ | bash   (maj : sentry-cli update)
# export SENTRY_DSN=''
# eval "$(sentry-cli bash-hook)"


SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Secrets et config : dans le .env à côté du script (voir env_example).
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
[ -f "$ENV_FILE" ] || { echo "[folder-borg] .env introuvable : $ENV_FILE (cp env_example .env)" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

PREFIX="${BORG_PREFIX:?BORG_PREFIX doit être renseigné dans le .env}"

# Clé SSH DÉDIÉE à ce dépôt (une clé = un dépôt sur borgwarehouse).
# Par défaut nommée d'après le préfixe pour cohabiter avec d'autres dépôts.
SSH_KEY="${SSH_KEY:-$SCRIPT_DIR/.ssh/${PREFIX}_ed25519}"


#### FILTRAGE ####
# 1) Exclusions rapides : décommenter/ajouter des patterns borg (--exclude).
EXCLUDES=(
  # '*/node_modules'
  # '*.log'
  # '*/.cache'
  # '*/tmp'
)
# 2) Filtrage avancé (gros dossier type Home) : si borg_patterns.txt existe à
#    côté de ce script, il est passé en --patterns-from (règles R / + / -).
#    Voir borg_patterns.txt.example.
PATTERNS_FILE="$SCRIPT_DIR/borg_patterns.txt"


#### PRÉPARATION ####
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

: "${BORG_REPO:?BORG_REPO doit être renseigné dans le .env}"
: "${BORG_PASSPHRASE:?BORG_PASSPHRASE doit être renseigné dans le .env}"
command -v borg >/dev/null || { echo "[folder-borg] borg introuvable dans le PATH" >&2; exit 1; }

DATE_NOW=$(date +%Y-%m-%d-%H-%M)

# Force l'usage de CETTE clé (et pas une autre de l'agent SSH).
if [ -f "$SSH_KEY" ]; then
  chmod 600 "$SSH_KEY" 2>/dev/null || true
  export BORG_RSH="/usr/bin/ssh -oStrictHostKeyChecking=accept-new -oIdentitiesOnly=yes -i $SSH_KEY"
else
  echo "[folder-borg] [INFO] aucune clé à $SSH_KEY — SSH utilisera la config système (agent/ssh_config)." >&2
fi

# Mode init : initialise le dépôt puis sort.
if [ "${1:-}" = "--init" ]; then
  echo "$DATE_NOW initialisation du dépôt borg ($BORG_REPO) avec repokey-blake2"
  /usr/bin/borg init -e repokey-blake2 "$BORG_REPO"
  exit 0
fi

: "${DUMPS_DIRECTORY:?DUMPS_DIRECTORY doit être renseigné dans le .env}"
[ -d "$DUMPS_DIRECTORY" ] || { echo "[folder-borg] dossier introuvable : $DUMPS_DIRECTORY" >&2; exit 1; }


#### BORG CREATE ####
create_args=(--exclude-caches)
if [ ${#EXCLUDES[@]} -gt 0 ]; then
  for pat in "${EXCLUDES[@]}"; do
    create_args+=(--exclude "$pat")
  done
fi
if [ -f "$PATTERNS_FILE" ]; then
  echo "[folder-borg] filtrage avancé via $PATTERNS_FILE"
  create_args+=(--patterns-from "$PATTERNS_FILE")
fi

echo "$DATE_NOW on crée l'archive borg"
/usr/bin/borg create -vs --compression lz4 \
  "${create_args[@]}" \
  "$BORG_REPO::$PREFIX-$DATE_NOW" \
  "$DUMPS_DIRECTORY"

echo "$DATE_NOW on prune les vieux borg :"
# --glob-archives : le prune ne touche QUE les archives de cette sauvegarde. Si
# deux sauvegardes partagent un depot, chacune garde sa retention — sans ce
# filtre, elles se rognent mutuellement, en silence.
/usr/bin/borg prune -v --list \
  --glob-archives "$PREFIX-*" \
  --keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1 --keep-yearly=-1 \
  "$BORG_REPO"

echo "$DATE_NOW terminé"
