#!/usr/bin/env bash
# Snapshot SQLite cohérent + archive borg vers borgwarehouse.
#
# Comme les autres exemples, il est piloté par un fichier .env placé à côté de
# lui (voir env_example) : aucun secret dans le script.
#
# Workflow :
#   1. Snapshot cohérent de chaque base SQLite via l'API Online Backup
#      (`sqlite3 .backup`), pendant que l'application continue de tourner.
#   2. Archive le dossier de snapshots dans un dépôt borg.
#   3. Prune les vieilles archives puis compacte le dépôt.
#
# Variables requises :
#   BORG_REPO         chemin ou URL ssh du dépôt borg (borgwarehouse)
#   BORG_PASSPHRASE   (ou BORG_PASSCOMMAND) passphrase du dépôt
#
# Variables optionnelles (avec valeurs par défaut) :
#   DATA_DIR          dossier contenant les .db (défaut : $APP_DIR/data)
#   APP_DIR           dossier de l'application  (défaut : dossier du script)
#   SNAPSHOT_DIR      où écrire le snapshot     (défaut : $APP_DIR/backup-snapshots)
#   BORG_PREFIX       préfixe des archives      (défaut : sqlite)
#   SSH_KEY           clé SSH dédiée au dépôt   (défaut : $APP_DIR/.ssh/${BORG_PREFIX}_ed25519)
#   KEEP_DAILY        borg prune --keep-daily   (défaut : 7)
#   KEEP_WEEKLY       borg prune --keep-weekly  (défaut : 4)
#   KEEP_MONTHLY      borg prune --keep-monthly (défaut : 6)
#
# Rappel borgwarehouse : une clé SSH = un dépôt. Générez une clé dédiée et
# collez sa partie publique dans le dépôt correspondant (voir README).
#
# Exemple crontab (tous les jours à 03:15) :
#   15 3 * * * BORG_REPO=ssh://borgwarehouse@localhost:2226/./674b31c6 \
#     BORG_PASSPHRASE='…' /chemin/backup_sqlite_example.sh >> /var/log/sqlite-borg.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-$SCRIPT_DIR}"

# Source .env si présent, pour éviter d'exporter les variables dans le cron.
if [ -f "$APP_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$APP_DIR/.env"
    set +a
fi

DATA_DIR="${DATA_DIR:-$APP_DIR/data}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-$APP_DIR/backup-snapshots}"
# BORG_PREFIX est le nom retenu partout. On accepte encore PREFIX pour ne pas
# casser un .env déjà en service : un préfixe qui change en silence, c'est un
# prune qui ne retrouve plus ses archives.
PREFIX="${BORG_PREFIX:-${PREFIX:-sqlite}}"
SSH_KEY="${SSH_KEY:-$APP_DIR/.ssh/${PREFIX}_ed25519}"

KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"

: "${BORG_REPO:?BORG_REPO must be set}"

# Une seule sauvegarde à la fois. Sans ce verrou, un lancement manuel qui tombe
# pendant le cron partagerait le même SNAPSHOT_DIR : le premier le supprime
# (rm -rf) pendant que l'autre archive encore, et on obtient une archive
# incomplète, silencieusement.
exec 9>"$SCRIPT_DIR/.backup-sqlite.lock"
flock -n 9 || { echo "[sqlite-borg] une sauvegarde est déjà en cours — abandon." >&2; exit 1; }

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK="${BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK:-yes}"
export BORG_RELOCATED_REPO_ACCESS_IS_OK="${BORG_RELOCATED_REPO_ACCESS_IS_OK:-yes}"

command -v sqlite3 >/dev/null || { echo "[sqlite-borg] sqlite3 introuvable dans le PATH" >&2; exit 1; }
command -v borg    >/dev/null || { echo "[sqlite-borg] borg introuvable dans le PATH"    >&2; exit 1; }

if [ ! -d "$DATA_DIR" ]; then
    echo "[sqlite-borg] dossier de données introuvable : $DATA_DIR" >&2
    exit 1
fi

# Force l'usage de CETTE clé pour joindre borgwarehouse (une clé = un dépôt).
if [ -f "$SSH_KEY" ]; then
    chmod 600 "$SSH_KEY" 2>/dev/null || true
    export BORG_RSH="${BORG_RSH:-/usr/bin/ssh -oStrictHostKeyChecking=accept-new -oIdentitiesOnly=yes -i $SSH_KEY}"
else
    echo "[sqlite-borg] [INFO] aucune clé à $SSH_KEY — SSH utilisera la config système." >&2
fi

# Snapshot cohérent de chaque .db (racine de DATA_DIR + un niveau databases/).
# On reproduit l'arborescence source : une restauration = `cp -r snapshot/* data/`.
rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR"

shopt -s nullglob
for src in "$DATA_DIR"/*.db "$DATA_DIR"/databases/*.db; do
    rel="${src#"$DATA_DIR"/}"
    dst="$SNAPSHOT_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    echo "[sqlite-borg] $(date -Is) snapshot de $rel"
    sqlite3 "$src" ".backup '$dst'"
done
shopt -u nullglob

if ! find "$SNAPSHOT_DIR" -name '*.db' -type f | grep -q .; then
    echo "[sqlite-borg] aucun .db snapshoté — abandon" >&2
    exit 1
fi

echo "[sqlite-borg] $(date -Is) création de l'archive borg"
borg create \
    --stats \
    --compression zstd,9 \
    "$BORG_REPO::${PREFIX}-{hostname}-{now:%Y-%m-%dT%H:%M:%S}" \
    "$SNAPSHOT_DIR"

echo "[sqlite-borg] $(date -Is) prune des vieilles archives"
borg prune \
    --list \
    --glob-archives "${PREFIX}-*" \
    --keep-daily   "$KEEP_DAILY" \
    --keep-weekly  "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    "$BORG_REPO"

echo "[sqlite-borg] $(date -Is) compactage du dépôt"
borg compact "$BORG_REPO"

echo "[sqlite-borg] $(date -Is) terminé"
