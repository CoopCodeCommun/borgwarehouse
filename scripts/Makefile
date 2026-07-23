# Table des matieres du dossier de sauvegarde. La logique vit dans les scripts.
# A copier avec les scripts sur la machine qui sauvegarde.
.PHONY: help init backup check list mount umount

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
	@echo "  make mount ARCHIVE=<nom>     ne monte qu'une archive"
	@echo "  make mount MOUNTPOINT=<rep>  ailleurs que dans /tmp/borg-mount"
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
