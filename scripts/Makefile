# Table des matieres du dossier de sauvegarde. La logique vit dans les scripts.
# A copier avec les scripts sur la machine qui sauvegarde.
.PHONY: help init backup check

# Le type de sauvegarde est lu dans le .env : folder | postgres | sqlite
TYPE := $(shell sed -n 's/^[[:space:]]*BACKUP_TYPE[[:space:]]*=[[:space:]]*//p' .env 2>/dev/null | head -n1)

help:
	@echo "Sauvegarde borg vers borgwarehouse — cibles disponibles :"
	@echo ""
	@echo "  make init      configure la sauvegarde (cle SSH, depot BWH, .env, cron)"
	@echo "  make backup    lance une sauvegarde maintenant"
	@echo "  make check     verifie que la derniere sauvegarde est restaurable"
	@echo ""
	@echo "Pour demarrer :  cp env_example .env && chmod 600 .env && make init"

init:
	@bash init_backup.sh

backup:
	@test -n "$(TYPE)" || { echo "BACKUP_TYPE absent du .env (folder | postgres | sqlite)" >&2; exit 1; }
	@bash backup_$(TYPE)_example.sh

check:
	@bash check_backup.sh
