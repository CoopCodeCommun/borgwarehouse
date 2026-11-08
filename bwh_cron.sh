#!/bin/sh
# Cron hôte : demande à BorgWarehouse de vérifier les dépôts
# (mail d'alerte si un backup n'arrive plus / si le stockage dépasse le quota).
# La clé est lue dans .env pour ne pas l'écrire en clair dans la crontab.
#   * * * * * /chemin/vers/borgwarehouse/bwh_cron.sh
cd "$(dirname "$0")" || exit 1
K=$(grep '^CRONJOB_KEY=' .env | cut -d= -f2)
for e in status storage; do
  curl -fsS -o /dev/null -X POST -H "Authorization: Bearer $K" \
    "http://localhost:3000/api/v1/cron/$e" || echo "bwh cron $e failed"
done
