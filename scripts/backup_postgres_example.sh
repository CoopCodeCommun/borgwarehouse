#!/bin/bash
set -euo pipefail

##### INSTRUCTION
#
# Sauvegarde d'une base (ou de toutes les bases) PostgreSQL vers borgwarehouse.
# Principe : dump SQL cohérent -> archive borg -> prune -> nettoyage du dump.
#
# CONFIGURATION : ce script ne contient aucun secret. Il lit son .env, placé à
# côté de lui (voir env_example). Un script est fait pour être copié, versionné,
# partagé — une passphrase écrite dedans finit tôt ou tard dans un dépôt git.
#
# 1- Copier ce script sur la machine qui a accès à PostgreSQL.
# 2- Choisir un BORG_PREFIX, puis générer une clé SSH DÉDIÉE à ce dépôt :
#      mkdir -p ./.ssh && chmod 700 ./.ssh
#      ssh-keygen -t ed25519 -N '' -f ./.ssh/madb_ed25519      # nom = $BORG_PREFIX
# 3- Créer un dépôt dans borgwarehouse, y coller ./.ssh/madb_ed25519.pub
# 4- Renseigner le .env :
#      cp env_example .env && chmod 600 .env
# 5- Initier le dépôt :   ./backup_postgres_example.sh --init
# 6- Sauvegarder :        ./backup_postgres_example.sh
# 7- Cron :               @daily bash /chemin/vers/backup_postgres_example.sh
#
# Auth PostgreSQL : renseignez PGPASSWORD dans le .env, ou utilisez un ~/.pgpass
# (chmod 600) ce qui reste préférable pour un cron.
#####

## Surveillance optionnelle via Sentry :
# export SENTRY_DSN=''
# eval "$(sentry-cli bash-hook)"


SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Secrets et config : dans le .env à côté du script (voir env_example).
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
[ -f "$ENV_FILE" ] || { echo "[pg-borg] .env introuvable : $ENV_FILE (cp env_example .env)" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# Connexion PostgreSQL (valeurs par défaut si absentes du .env).
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-}"   # ou vide, et un ~/.pgpass (chmod 600)
# Base à sauvegarder. Vide = TOUTES les bases (pg_dumpall).
PGDATABASE="${PGDATABASE:-}"

PREFIX="${BORG_PREFIX:?BORG_PREFIX doit être renseigné dans le .env}"

# Clé SSH dédiée à ce dépôt (une clé = un dépôt sur borgwarehouse)
SSH_KEY="${SSH_KEY:-$SCRIPT_DIR/.ssh/${PREFIX}_ed25519}"

# Dossier de travail pour le dump (supprimé après l'archivage)
DUMP_DIR="${DUMP_DIR:-$SCRIPT_DIR/pg-dump-$PREFIX}"


#### PRÉPARATION ####
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

# Une seule sauvegarde à la fois. Sans ce verrou, un lancement manuel qui tombe
# pendant le cron partagerait le même DUMP_DIR : le premier à finir le supprime
# (trap EXIT) pendant que l'autre archive encore, et on obtient une archive SANS
# DUMP, silencieusement.
exec 9>"$SCRIPT_DIR/.backup-pg.lock"
flock -n 9 || { echo "[pg-borg] une sauvegarde est déjà en cours — abandon." >&2; exit 1; }

: "${BORG_REPO:?BORG_REPO doit être renseigné dans le .env}"
: "${BORG_PASSPHRASE:?BORG_PASSPHRASE doit être renseigné dans le .env}"
command -v borg    >/dev/null || { echo "[pg-borg] borg introuvable dans le PATH" >&2; exit 1; }
command -v pg_dump >/dev/null || { echo "[pg-borg] pg_dump introuvable dans le PATH" >&2; exit 1; }

DATE_NOW=$(date +%Y-%m-%d-%H-%M)

if [ -f "$SSH_KEY" ]; then
  chmod 600 "$SSH_KEY" 2>/dev/null || true
  export BORG_RSH="/usr/bin/ssh -oStrictHostKeyChecking=accept-new -oIdentitiesOnly=yes -i $SSH_KEY"
else
  echo "[pg-borg] [INFO] aucune clé à $SSH_KEY — SSH utilisera la config système." >&2
fi

# Mode init
if [ "${1:-}" = "--init" ]; then
  echo "$DATE_NOW initialisation du dépôt borg ($BORG_REPO) avec repokey-blake2"
  /usr/bin/borg init -e repokey-blake2 "$BORG_REPO"
  exit 0
fi


#### DUMP POSTGRES ####
# Nettoyage garanti du dump même en cas d'erreur.
trap 'rm -rf "$DUMP_DIR"' EXIT
rm -rf "$DUMP_DIR"
mkdir -p "$DUMP_DIR"

if [ -n "$PGDATABASE" ]; then
  DUMP_FILE="$DUMP_DIR/$PGDATABASE.dump"
  echo "$DATE_NOW dump de la base '$PGDATABASE' (format custom)"
  # -Fc : format compressé, restaurable avec pg_restore
  pg_dump -Fc "$PGDATABASE" -f "$DUMP_FILE"
else
  DUMP_FILE="$DUMP_DIR/all-databases.sql"
  echo "$DATE_NOW dump de TOUTES les bases (pg_dumpall)"
  command -v pg_dumpall >/dev/null || { echo "[pg-borg] pg_dumpall introuvable" >&2; exit 1; }
  pg_dumpall -f "$DUMP_FILE"
fi

# Garde-fou : un dump vide = on n'archive pas.
if [ ! -s "$DUMP_FILE" ]; then
  echo "[pg-borg] dump vide ($DUMP_FILE) — abandon" >&2
  exit 1
fi


#### BORG CREATE ####
echo "$DATE_NOW on crée l'archive borg"
/usr/bin/borg create -vs --compression lz4 \
  "$BORG_REPO::$PREFIX-$DATE_NOW" \
  "$DUMP_DIR"

echo "$DATE_NOW on prune les vieux borg :"
# --glob-archives : le prune ne touche QUE les archives de cette sauvegarde. Si
# deux sauvegardes partagent un depot, chacune garde sa retention — sans ce
# filtre, elles se rognent mutuellement, en silence.
/usr/bin/borg prune -v --list \
  --glob-archives "$PREFIX-*" \
  --keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1 --keep-yearly=-1 \
  "$BORG_REPO"

echo "$DATE_NOW terminé"
