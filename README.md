# Borgwarehouse install :

```bash
# récupérez le dépot :
git clone https://github.com/CoopCodeCommun/borgwarehouse

# créez les dossiers a la main (sinon c'est compose qui le fait et ils seront en root. les app n'y auront pas accès) :
mkdir config ssh ssh_host repos tmp logs sync_config sync_data

# Donner les droits des dossiers aux users des conteneurs :
sudo chown 1001:1001 config ssh ssh_host repos tmp logs sync_config sync_data

# Copier l'env exemple et remplir les variables
#   FQDN / NEXTAUTH_URL : le domaine de BWH
#   SYNC_DOMAIN : nom d'hôte seul, SANS https:// (il finit dans la règle Host() de Traefik)
#   NEXTAUTH_SECRET / CRONJOB_KEY : openssl rand -hex 32
cp env_example .env && chmod 600 .env

# Lancez la stack
docker compose up -d && docker compose logs -f
```

Prérequis : la stack [TraefikV3](https://github.com/CoopCodeCommun/TraefikV3)
(réseau `frontend`, résolveur `myresolver`, CrowdSec appliqué sur `websecure`)
et les DNS de `FQDN` et `SYNC_DOMAIN` pointant sur le serveur.

Ports à ouvrir sur le routeur / pare-feu :

| Port | Pour |
|---|---|
| 80, 443 | Traefik (interfaces BWH et Syncthing) |
| `SSH_SERVER_PORT` (2222) /tcp | SSH de borg — les clients qui envoient leurs sauvegardes |
| 22000 /tcp + /udp | Syncthing entre serveurs |

L'interface BWH (3000) n'est publiée que sur `127.0.0.1` : depuis l'extérieur, on
passe uniquement par Traefik. Idem pour Syncthing (8384 n'est pas publié).

admin/admin pour la première connection : changez les creds et ajoutez votre email !

### ⚠️ Mot de passe Syncthing : tout de suite après le `up`

Un Syncthing neuf **n'a pas de mot de passe**, et derrière Traefik son interface est
**ouverte à tout Internet** dès que le conteneur démarre (le « host check » ne
protège pas ici). Poser un mot de passe immédiatement, via l'API locale :

```bash
KEY=$(docker exec syncthing sh -c 'grep -o "<apikey>[^<]*" /config/config.xml | cut -d">" -f2')
IP=$(docker inspect syncthing -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
PW=$(openssl rand -base64 18 | tr -d '/+=')
printf 'SYNCTHING_GUI_USER=admin\nSYNCTHING_GUI_PASSWORD=%s\n' "$PW" > sync_gui_credentials.txt
chmod 600 sync_gui_credentials.txt
curl -X PATCH -H "X-API-Key: $KEY" -H 'Content-Type: application/json' \
  -d "{\"user\":\"admin\",\"password\":\"$PW\"}" "http://$IP:8384/rest/config/gui"
# (la connexion est coupée par le redémarrage de la GUI : c'est normal)
```

Le mot de passe est dans `sync_gui_credentials.txt` (ignoré par git) : à mettre au coffre.

### Create a cron on host ( not inside docker ) : 

BW a besoin d'un cron qui lui demande d'aller vérifier que tout les dépots sont bien a jour. Si l'un d'entre eux a dépassé son uptime, il envoie un mail.
Ce qui est le but principal recherché de cette stack : prévenir lorsqu'un backup n'arrive pas.

Le script `bwh_cron.sh` lit `CRONJOB_KEY` dans `.env` (la clé n'apparaît pas en
clair dans la crontab). `crontab -e` :

```bash
* * * * * /chemin/vers/borgwarehouse/bwh_cron.sh
```

Pensez aussi aux variables `MAIL_SMTP_*` du `.env` : sans SMTP, pas d'alerte.


# Sauvegarder une nouvelle application

C'est la procédure à suivre pour tout nouveau déploiement (un Nextcloud, une
base PostgreSQL, une app maison…). Le dossier [`scripts/`](./scripts) est un
**kit à copier** sur la machine à sauvegarder : trois commandes, et la sauvegarde
est en place, planifiée, vérifiée et surveillée.

```bash
# Sur la machine qui héberge l'application, à côté de ce qu'on sauvegarde :
git clone https://github.com/CoopCodeCommun/borgwarehouse /tmp/bw
cp -r /tmp/bw/scripts /opt/nextcloud/backup && cd /opt/nextcloud/backup

cp env_example .env && chmod 600 .env
$EDITOR .env         # BACKUP_TYPE=folder + DUMPS_DIRECTORY=/var/lib/nextcloud

make init            # clé SSH, dépôt BWH, borg init, cron, 1re sauvegarde
make check           # est-ce vraiment restaurable ?
```

`make init` enchaîne tout ce que l'ancienne procédure manuelle demandait de faire
à la main : il génère la clé SSH dédiée, crée le dépôt sur borgwarehouse **via
son API**, tire une passphrase, initialise le dépôt, exporte sa clé, pose le cron
et lance une première sauvegarde qu'il vérifie.

Deux choses te seront demandées :

- **Un token API** (*Account → Integrations*), avec la permission **`create`
  uniquement** : c'est le seul appel que fait `make init`. Sans token, il affiche
  la clé publique et te laisse créer le dépôt à la main dans l'interface.
- **De confirmer que tu as mis la passphrase au coffre.** Ce n'est pas une
  formalité : la passphrase, la clé exportée (`borg key export`) et l'identifiant
  du dépôt sont le seul maillon que la sauvegarde ne peut pas se sauvegarder
  elle-même. Sans eux, les archives sont un bloc chiffré définitivement illisible.

`make init` est **rejouable** : API injoignable, `borg init` raté, Ctrl-C en plein
milieu — relance-le, il reprend ce qui existe. Le seul cas où il refuse, c'est
quand le dépôt **contient déjà des archives**, car régénérer une passphrase les
rendrait illisibles.

## Choisir le type

| `BACKUP_TYPE` | Pour quoi |
|---|---|
| `folder` | Un dossier complet — Nextcloud, `/home`, un volume applicatif |
| `postgres` | Une base, ou toutes (`pg_dumpall`) |
| `sqlite` | Bases SQLite (snapshot cohérent) |

Une application dockerisée dont la base tourne dans un conteneur ? Le dépôt
[**ghost**](https://github.com/CoopCodeCommun/ghost) applique le même kit à une
stack Docker Compose (dump via `docker compose exec`) : c'est le modèle à copier.

Rappel borgwarehouse : **une clé SSH = un dépôt**. Une machine qui sauvegarde
plusieurs cibles a besoin d'une clé par dépôt — `make init` s'en occupe, et
plusieurs sauvegardes cohabitent sans collision sur la même machine.

## Vérifier — vraiment

Qu'une archive existe ne prouve rien. `make check` répond à la seule question qui
compte, *est-ce restaurable ?*, sans rien restaurer : archive récente, contenu
attendu, et surtout **données exploitables** — un dump PostgreSQL est déroulé
entièrement dans `pg_restore`, une base SQLite doit avoir un en-tête valide. Un
dump tronqué (disque plein, process tué) a une taille crédible, se trouve bien
dans l'archive, et ne se restaure pas.

Il sort en code non nul si quelque chose cloche : branchable tel quel sur un
monitoring. Détails dans le [README de `scripts/`](./scripts/README.md).

Et n'oublie pas l'autre filet : borgwarehouse t'envoie un mail si un dépôt ne
reçoit plus rien. Un cron qui échoue en silence, c'est un backup qui n'existe pas.

## À la main (si tu ne veux pas du kit)

<details>
<summary>L'ancienne procédure, dépliée</summary>

- Générer une clé SSH avec l'utilisateur qui lancera le script de sauvegarde
- Créer un dépôt sur l'UX de borgwarehouse (BWH) en y ajoutant la clé publique
- Cliquer sur la petite icône en haut à droite du dépôt pour copier son adresse SSH
- Initier le dépôt avec l'utilisateur qui lancera le script :

`borg init -e repokey-blake2 <adresse ssh>`

- Exemple sur le même serveur :
`borg init -e repokey-blake2 ssh://borgwarehouse@localhost:2226/./155b31d4`

- Exemple sur un serveur distant :
`borg init -e repokey-blake2 ssh://borgwarehouse@borgwarehouse.moi.me:2226/./155b31d4`

Le dépôt n'est pas initialisé dans le dossier courant, mais bien dans le dossier
monté du conteneur BWH.

- Générer une passphrase très forte et la stocker dans un coffre-fort numérique.
  Garder aussi l'id du dépôt (ex : `c7a620ed`).
- Exporter la clé du dépôt au même endroit :

```
borg key export <adresse ssh>
```

</details>

Autre exemple externe pour Postgres : https://github.com/TiBillet/Lespass/blob/PreProd/cron/saveDb.sh


# Syncthing : réplication des dépôts entre serveurs

Chaque serveur qui fait tourner cette stack **envoie** ses propres dépôts borg aux
autres, et **reçoit** ceux des autres. Deux dossiers, deux rôles, à ne jamais mélanger :

| Chemin dans le conteneur | Sur l'hôte | Contenu | Type de partage |
|---|---|---|---|
| `/home/borgwarehouse/repos` | `./repos` (`BORG_REPOSITORY_PATH`) | les dépôts de **ce** serveur (ceux que BWH gère) | **Envoi seulement** |
| `/sync_data/<serveur>` | `./sync_data/<serveur>` | les copies des dépôts **des autres** serveurs | **Réception seulement** |

1. Poser le mot de passe de l'interface (voir plus haut), puis se connecter.
2. Ajouter les autres serveurs comme appareils (échange des Device ID).
3. **Partager ses propres dépôts** : nouveau partage, chemin
   `/home/borgwarehouse/repos`, un ID/nom propre au serveur (ex. `BWH maison`),
   onglet avancé → **Envoi seulement**, partagé avec tous les autres serveurs.
4. **Accepter les partages des autres** : chemin `/sync_data/<nom du serveur>`,
   onglet avancé → **Réception seulement**.

Ne jamais recevoir le partage d'un autre serveur dans `/home/borgwarehouse/repos` :
ses dépôts se mélangeraient à ceux de BWH (et la réception seule les traiterait
comme des modifications locales à annuler). Ne rien mettre d'autre que les dépôts
borg dans `repos`.

À savoir :

- Une suppression ou une corruption (rançongiciel, `borg delete`…) côté émetteur
  **se réplique** chez tous les récepteurs. Protections : mode *append-only* sur
  les dépôts dans BWH, et/ou snapshots (ZFS, versioning Syncthing) de `sync_data`
  côté récepteurs.
- Une copie prise pendant une sauvegarde en cours peut être momentanément
  incohérente ; elle redevient cohérente une fois la synchro terminée.
- Les copies sont chiffrées (repokey) : restaurer depuis un autre serveur demande
  la passphrase du dépôt, comme sur l'original.
