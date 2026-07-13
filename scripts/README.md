# Sauvegarder une application vers borgwarehouse

Ce dossier est un **kit à copier** sur la machine qui héberge l'application à
sauvegarder. Trois commandes, et la sauvegarde est en place, vérifiée, et
surveillée.

```bash
cp env_example .env && chmod 600 .env
$EDITOR .env          # BACKUP_TYPE + quoi sauvegarder
make init             # clé SSH, dépôt BWH, borg init, cron, 1re sauvegarde
make check            # est-ce vraiment restaurable ?
```

## Les trois cibles

| Cible | Ce qu'elle fait |
|---|---|
| `make init` | Génère la clé SSH, crée le dépôt sur borgwarehouse, tire une passphrase, `borg init`, pose le cron, lance une première sauvegarde et la vérifie |
| `make backup` | Lance une sauvegarde maintenant |
| `make check` | Vérifie que la dernière sauvegarde est **restaurable** |

## Choisir son type

Le `.env` commence par un `BACKUP_TYPE`, qui détermine le script utilisé :

| `BACKUP_TYPE` | Script | Cas d'usage |
|---|---|---|
| `folder` | [`backup_folder_example.sh`](./backup_folder_example.sh) | Un dossier complet — Nextcloud, `/home`, un volume applicatif |
| `postgres` | [`backup_postgres_example.sh`](./backup_postgres_example.sh) | Une base, ou toutes (`pg_dumpall`) |
| `sqlite` | [`backup_sqlite_example.sh`](./backup_sqlite_example.sh) | Bases SQLite (snapshot cohérent via `.backup`) |

Pour une application dockerisée dont la base tourne dans un conteneur, voir
plutôt [le dépôt Ghost](https://github.com/CoopCodeCommun/ghost), qui applique
exactement le même kit à une stack Docker Compose (dump via
`docker compose exec`).

## Aucun secret dans les scripts

Tous lisent le `.env` placé à côté d'eux, que git ignore. Un script est fait pour
être copié, versionné, partagé : une passphrase écrite dedans finit tôt ou tard
poussée sur une forge, au premier `git add -A` distrait.

`make init` écrit lui-même dans le `.env` les trois variables du dépôt
(`BORG_PREFIX`, `BORG_REPO`, `BORG_PASSPHRASE`). Il n'y a rien à y saisir à la
main.

## Une clé SSH par dépôt

Côté serveur, borgwarehouse associe **une** clé publique à **un** dépôt, et
restreint cette clé à ce seul dépôt.

> **Une clé SSH = un dépôt.** Une machine qui sauvegarde plusieurs cibles a
> besoin d'une clé par dépôt.

`make init` s'en occupe : la clé est nommée d'après le préfixe
(`./.ssh/<prefix>_ed25519`), donc plusieurs sauvegardes cohabitent sur la même
machine sans collision. Chacune pose sa propre ligne de cron.

## Le token borgwarehouse

`make init` peut créer le dépôt tout seul, via l'API. Il ne fait **qu'un seul
appel** (`POST /api/v1/repositories`) : un token avec la permission **`create`
uniquement** suffit (*Account → Integrations*). Tout le reste — `init`, `create`,
`prune`, `list` — passe par SSH avec la clé dédiée.

Un token *create-only* qui fuiterait ne permettrait ni de lister ni de supprimer
tes dépôts, au pire d'en créer des parasites. Il n'est de toute façon jamais
stocké : saisi au clavier, il ne sert qu'une fois.

Sans token, `make init` affiche la clé publique et te laisse créer le dépôt à la
main dans l'interface, puis coller son adresse.

## `make check` : la seule question qui compte

Vérifier qu'une archive *existe* ne dit rien. `make check` répond à *est-ce
restaurable ?*, sans rien restaurer :

1. **Fraîcheur** — la dernière archive date de moins de 25 h. Sinon le cron est
   mort, et personne ne l'avait remarqué.
2. **Contenu** — l'archive contient bien des fichiers, et ceux qu'on attend.
3. **Exploitabilité** — et c'est là que ça se joue :

| Type | Ce qu'on vérifie |
|---|---|
| `postgres` (custom) | Le dump est déroulé **entièrement** dans `pg_restore -f /dev/null`. Un fichier tronqué échoue. Vérifier seulement l'en-tête ne prouverait rien : la table des matières est au début du fichier. |
| `postgres` (`pg_dumpall`) | Présence du marqueur `-- PostgreSQL database cluster dump complete`, que `pg_dumpall` écrit en dernier |
| `sqlite` | Chaque `.db` commence bien par `SQLite format 3` |
| `folder` | Les fichiers de `DUMPS_DIRECTORY` sont bien dans l'archive, et non vides |

Un dump tronqué — disque plein, process tué en plein vol — a une taille crédible,
se trouve bien dans l'archive, et ne se restaure pas. C'est précisément ce que ce
test attrape.

Limite assumée pour `folder` : on ne peut pas prouver que des fichiers
quelconques sont « exploitables », il n'y a rien à désérialiser. On vérifie leur
présence, pas leur sens.

`make check` sort en code non nul si quoi que ce soit cloche : utilisable tel quel
dans un monitoring.

**Ce qu'il ne teste pas** : ta copie de coffre-fort. Il utilise le `.env` de la
machine, pas la passphrase que tu as archivée ailleurs — or c'est celle-là, et
elle seule, qui servira le jour où la machine aura brûlé. Vérifie une fois, depuis
une autre machine, qu'un `borg list` passe avec les éléments du coffre.

## Deux protections discrètes

**Un verrou** (`flock`) sur les scripts PostgreSQL et SQLite : sans lui, un
lancement manuel tombant pendant le cron partagerait le même dossier temporaire,
le premier à finir le supprimerait pendant que l'autre archive encore, et on
obtiendrait une archive **sans dump**.

**Le `prune` ne touche que les archives de cette sauvegarde**
(`--glob-archives "$PREFIX-*"`). Si deux sauvegardes partagent un dépôt, sans ce
filtre elles se rognent mutuellement leur rétention, en silence.

## Rétention

7 jours glissants, 30 quotidiennes, 12 hebdomadaires, puis **toutes** les
mensuelles et annuelles.

## Filtrer (type `folder`)

Trois niveaux, tous en borg standard :

1. **Exclusions rapides** — le tableau `EXCLUDES=( … )` en tête du script
   (`*/node_modules`, `*.log`…), passées en `--exclude`.
2. **`--exclude-caches`** — activé par défaut : saute les dossiers marqués
   `CACHEDIR.TAG`.
3. **Filtrage avancé** — pour un gros dossier (type `/home`), copier
   [`borg_patterns.txt.example`](./borg_patterns.txt.example) en
   `borg_patterns.txt` à côté du script. S'il existe, il est passé en
   `--patterns-from` : on raisonne par inclusion/exclusion (`R` / `+` / `-`) au
   lieu d'une liste d'exclusions interminable.

## Restaurer

```bash
borg list  "$BORG_REPO"                    # lister les archives
borg extract "$BORG_REPO::<archive>"       # extraire dans le dossier courant

# PostgreSQL (custom) :  pg_restore -d <base> chemin/vers/<base>.dump
# PostgreSQL (dumpall) :  psql -f chemin/vers/all-databases.sql
# SQLite  : les .db du snapshot sont directement utilisables (cp -r)
# Dossier : les fichiers sont déjà là
```

## Surveillance

Deux filets, complémentaires :

- **`make check`** dit si la dernière sauvegarde est restaurable.
- **borgwarehouse** envoie un mail si le dépôt ne reçoit plus rien (alerte réglée
  par `make init`). C'est le seul mécanisme qui prévient qu'une sauvegarde **n'est
  pas arrivée** — un cron qui échoue en silence, c'est un backup qui n'existe pas.

Chaque script contient par ailleurs un hook **Sentry** commenté en tête, pour être
alerté si le script lui-même échoue.
