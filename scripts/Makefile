# Table des matieres du dossier de sauvegarde. La logique vit dans les scripts.
# A copier avec les scripts sur la machine qui sauvegarde.
.PHONY: help init backup check list mount umount archive

# Le type de sauvegarde est lu dans le .env : folder | postgres | sqlite
TYPE := $(shell sed -n 's/^[[:space:]]*BACKUP_TYPE[[:space:]]*=[[:space:]]*//p' .env 2>/dev/null | head -n1)

# Point de montage pour 'make mount'. Volontairement hors du dossier sauvegarde :
# monter le depot dedans exposerait la prochaine sauvegarde a se parcourir
# elle-meme.
MOUNTPOINT ?= /tmp/borg-mount

help:
	@echo "Sauvegarde borg vers borgwarehouse — cibles disponibles :"
	@echo ""
	@echo "  make init      configure la sauvegarde (cle SSH, depot BWH, .env, cron)"
	@echo "  make backup    lance une sauvegarde maintenant"
	@echo "  make check     verifie que la derniere sauvegarde est restaurable"
	@echo "  make list      liste les archives du depot"
	@echo "  make mount     monte les archives en lecture seule pour piocher dedans"
	@echo "  make umount    demonte"
	@echo ""
	@echo "  make archive   .tar du depot entier, pour le recopier (depot LOCAL seulement)"
	@echo ""
	@echo "  make mount ARCHIVE=<nom>     ne monte qu'une archive"
	@echo "  make mount MOUNTPOINT=<rep>  ailleurs que dans /tmp/borg-mount"
	@echo "  make archive TAR=<chemin>    ecrit le .tar ailleurs"
	@echo ""
	@echo "Pour demarrer :  cp env_example .env && chmod 600 .env && make init"

init:
	@bash init_backup.sh

backup:
	@test -n "$(TYPE)" || { echo "BACKUP_TYPE absent du .env (folder | postgres | sqlite)" >&2; exit 1; }
	@bash backup_$(TYPE)_example.sh

check:
	@bash check_backup.sh

# Les cibles ci-dessous parlent au depot directement. Elles rejouent le meme
# BORG_RSH que les scripts de sauvegarde : la cle SSH DEDIEE a ce depot, et elle
# seule (-oIdentitiesOnly=yes), sans quoi l'agent SSH proposerait une autre cle
# et borgwarehouse refuserait la connexion.
BORG_ENV = set -a; . ./.env; set +a; \
	   cle="$(CURDIR)/.ssh/$$BORG_PREFIX""_ed25519"; \
	   test ! -f "$$cle" || export BORG_RSH="/usr/bin/ssh -oStrictHostKeyChecking=accept-new -oIdentitiesOnly=yes -i $$cle";

list:
	@$(BORG_ENV) borg list "$$BORG_REPO"

# Monte les archives en FUSE, en LECTURE SEULE : on navigue dedans avec un
# explorateur de fichiers et on copie ce qu'on veut, sans tout extraire.
#   make mount                     tout le depot (une archive = un dossier)
#   make mount ARCHIVE=monapp-2026-07-23-18-00
mount:
	@command -v borg >/dev/null || { echo "[mount] borg introuvable" >&2; exit 1; }
	@$(BORG_ENV) \
	 mkdir -p "$(MOUNTPOINT)"; \
	 cible="$$BORG_REPO"; \
	 test -z "$(ARCHIVE)" || cible="$$BORG_REPO::$(ARCHIVE)"; \
	 echo "[mount] $$cible -> $(MOUNTPOINT)"; \
	 if borg mount -o ro "$$cible" "$(MOUNTPOINT)"; then \
	   echo "[mount] monte. Demonter avec :  make umount"; \
	 else \
	   echo >&2; \
	   echo "[mount] Si le message ci-dessus dit 'no FUSE support', il manque le" >&2; \
	   echo "        binding FUSE de python. Sur Debian/Ubuntu (borg tourne sur" >&2; \
	   echo "        /usr/bin/python3) :   sudo apt install python3-llfuse" >&2; \
	   exit 1; \
	 fi

umount:
	@borg umount "$(MOUNTPOINT)" && echo "[umount] $(MOUNTPOINT) demonte"

# Fabrique un .tar du depot ENTIER, pour le recopier d'un bloc (autre disque,
# coffre, machine distante).
#
# DEPOT LOCAL SEULEMENT, et la cible refuse d'aller plus loin sinon. Un depot
# borgwarehouse est derriere une cle SSH restreinte a 'borg serve' : on n'a
# aucun acces shell dessus, donc ni tar ni rsync du dossier distant. Ce n'est
# pas une limite du Makefile, c'est le modele de securite de BWH — et c'est
# voulu. Pour recuperer des donnees d'un depot distant, on exporte le CONTENU
# d'une archive (borg export-tar), pas le depot ; la cible l'indique.
#
# Trois precautions sur le tar lui-meme :
#  - 'borg with-lock' : le tar est pris SOUS LE VERROU du depot. Sans lui, une
#    sauvegarde qui demarrerait pendant l'archivage donnerait un .tar pris en
#    plein milieu d'une ecriture, donc un depot copie corrompu — et on ne s'en
#    apercevrait qu'en essayant de restaurer.
#  - on exclut lock.exclusive / lock.roster, sinon le tar embarque le verrou
#    qu'il vient lui-meme de poser et la copie arrive avec un lock mort.
#  - pas de compression : les donnees borg sont deja compressees et chiffrees.
#
# Le .tar contient le depot chiffre, PAS la passphrase (qui vit dans le .env).
# Un .tar seul ne restaure rien : garde passphrase et 'borg key export' au
# coffre, et de preference PAS sur le meme support que le .tar.
archive:
	@test -f .env || { echo "[archive] .env absent" >&2; exit 1; }
	@$(BORG_ENV) \
	 case "$$BORG_REPO" in \
	   ssh://*|*@*:*) \
	     echo "[archive] depot DISTANT : $$BORG_REPO" >&2; \
	     echo "[archive] impossible d'en faire un .tar — une cle borgwarehouse est" >&2; \
	     echo "          restreinte a 'borg serve', sans acces shell : ni tar ni" >&2; \
	     echo "          rsync du dossier distant." >&2; \
	     echo >&2; \
	     echo "          Pour sortir le CONTENU d'une archive en .tar :" >&2; \
	     echo "            make list                     # choisir une archive" >&2; \
	     echo "            borg export-tar \\" >&2; \
	     echo "              \"$$BORG_REPO::<archive>\" sortie.tar" >&2; \
	     echo >&2; \
	     echo "          Pour dupliquer un depot distant vers un depot local :" >&2; \
	     echo "            borg init -e repokey-blake2 /chemin/copie" >&2; \
	     echo "            # puis rejouer les archives une a une (mount + create)" >&2; \
	     exit 1;; \
	 esac; \
	 test -d "$$BORG_REPO" || { echo "[archive] depot introuvable : $$BORG_REPO" >&2; exit 1; }; \
	 out="$(TAR)"; test -n "$$out" || out="$$BORG_REPO.tar"; \
	 case "$$(readlink -f "$$out")" in \
	   "$$(readlink -f "$$BORG_REPO")"/*) \
	     echo "[archive] le .tar ne peut pas etre ecrit dans le depot lui-meme." >&2; exit 1;; \
	 esac; \
	 taille=$$(du -sk "$$BORG_REPO" | cut -f1); \
	 dispo=$$(df -Pk "$$(dirname "$$out")" | tail -1 | awk '{print $$4}'); \
	 echo "[archive] depot  : $$BORG_REPO ($$((taille/1024)) Mo)"; \
	 echo "[archive] sortie : $$out ($$((dispo/1024)) Mo libres)"; \
	 test "$$dispo" -gt "$$taille" || { echo "[archive] place insuffisante." >&2; exit 1; }; \
	 test ! -f "$$out" || echo "[archive] un fichier existe deja a cette adresse, il sera remplace."; \
	 echo "[archive] tar sous verrou du depot (aucune sauvegarde ne peut ecrire pendant)..."; \
	 borg with-lock "$$BORG_REPO" \
	   tar -cf "$$out" --exclude=lock.exclusive --exclude=lock.roster \
	   -C "$$(dirname "$$BORG_REPO")" "$$(basename "$$BORG_REPO")" || exit 1; \
	 echo "[archive] termine : $$(ls -lh "$$out" | awk '{print $$5}')"; \
	 echo "[archive] restauration depuis ce .tar :"; \
	 echo "            tar -xf $$(basename "$$out") -C /destination"; \
	 echo "            BORG_RELOCATED_REPO_ACCESS_IS_OK=yes \\"; \
	 echo "              borg list /destination/$$(basename "$$BORG_REPO")"; \
	 echo "          (borg demande confirmation : le depot n'est plus a son chemin d'origine)"
