# Borgwarehouse install :

```bash
# récupérez le dépot :
git clone https://github.com/CoopCodeCommun/borgwarehouse

# créez les dossiers a la main (sinon c'est compose qui le fait et ils seront en root. les app n'y auront pas accès) :
mkdir config ssh ssh_host repos tmp logs sync_config sync_data

# Donner les droits des dossiers aux users des conteneurs :
sudo chown 1001:1001 config ssh ssh_host repos tmp logs sync_config sync_data

# Copier l'env exemple et remplir les variables
cp env_example .env

# Lancez la stack
docker compose up -d && docker compose logs -f
```

admin/admin pour la première connection : changez les creds et ajoutez votre email !

### Create a cron on host ( not inside docker ) : 

BW a besoin d'un cron qui lui demande d'aller vérifier que tout les dépots sont bien a jour. Si l'un d'entre eux a dépassé son uptime, il envoie un mail.
Ce qui est le but principal recherché de cette stack : prévenir lorsqu'un backup n'arrive pas.

```bash
* * * * * curl --request POST --url 'http://localhost:3000/api/v1/cron/status' --header 'Authorization: Bearer CRONJOB_KEY' ; curl --request POST --url 'http://localhost:3000/api/v1/cron/storage' --header 'Authorization: Bearer CRONJOB_KEY'
```


# Créer un nouveau Dépot :

- Aller dans le serveur et le dossier à sauvegarder
- Générer une clé ssh si ce n'est pas déja fait avec l'utilisateur qui va lancer le script de sauvegarde
- Créer un dépot sur l'UX de borgwarehouse (BWH) en ajoutant la clé publique
- clic sur la ptite icone en haut a droite du nouvel objet backup sur BWH pour copier l'adresse ssh
- retourner sur le dossier de sauvegarde et initier le dépot avec l'user qui lancera le script en faisant : 

`borg init -e repokey-blake2 <adresse ssh>`

- Exemple si dans le même serveur : 
`borg init -e repokey-blake2 ssh://borgwarehouse@localhost:2226/./155b31d4`

- Exemple si serveur distant : 
`borg init -e repokey-blake2 ssh://borgwarehouse@borgwarehouse.moi.me:2226/./155b31d4`

Le dépot ne sera pas initialisé sur le dossier courant, mais bien dans le dossier monté du conteneur BWH.

- générer et renseigner un mot de passe super super super fort et le stocker dans un coffre fort numérique. Garder aussi l'id du repo au cazou ( ex: c7a620ed )

- Backuper la PASSPHRASE au même endroit que la clé :
```
borg key export <adresse ssh> ./key && cat ./key && rm ./key
```


## Écrire un script de backup et le lancer régulièrement. 

Exemple pour une base postgres : 
- https://github.com/TiBillet/Lespass/blob/PreProd/cron/saveDb.sh

Exemple pour un dossier complet (attention a qui lance le script ! root ou user ? )
- https://github.com/CoopCodeCommun/borgwarehouse/blob/main/backup_folder_example.sh


# Syncthing

Il a été lancé avec le up et est configuré pour avoir le dossier repo ( le même ou borg mets les repo ) dans /home/borgwarehouse/repos

- se connecter à l'interface et ajouter un user / password
- créez un nouveau partage :
	- le chemin racide du partage doit être /home/borgwarehouse/repos 
	- dans l'onglet avancé, selectionnez bien Envoi seulement

Attention, choisir ce chemin que pour synchroniser le dossier borg
ne pas rajouter dans le futur d'autres dossier sync depuis synthing dans ce dossier
utiliser pour cela le dossier /sync_data