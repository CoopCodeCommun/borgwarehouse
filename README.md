# Borgwarehouse install :

``` 
git clone https://github.com/CoopCodeCommun/borgwarehouse
mkdir config ssh ssh_host repos tmp logs sync_config sync_data
sudo chown 1001:1001 config ssh ssh_host repos tmp logs sync_config sync_data
cp env_example .env
```

- Modifiez le .env pour ajouter les variables et docker compose up -d
- admin/admin pour la première connection : changez les creds et ajoutez votre email !

### Create a cron on host ( not inside docker ) : 
```
# * * * * * curl --request POST --url 'http://localhost:3000/api/v1/cron/status' --header 'Authorization: Bearer CRONJOB_KEY' ; curl --request POST --url 'http://localhost:3000/api/v1/cron/storage' --header 'Authorization: Bearer CRONJOB_KEY'
```


# Syncthing

Il a été lancé avec le up et est configuré pour avoir le dossier repo ( le même ou borg mets les repo ) dans /home/borgwarehouse/repos

- se connecter à l'interface et ajouter un user / password
- créez un nouveau partage :
	- le chemin racide du partage doit être /home/borgwarehouse/repos 
	- dans l'onglet avancé, selectionnez bien Envoi seulement

Attention, choisir ce chemin que pour synchroniser le dossier borg
ne pas rajouter dans le futur d'autres dossier sync depuis synthing dans ce dossier
utiliser pour cela le dossier /sync_data

# Créer un nouveau Dépot :

- Aller dans le serveur et le dossier à sauvegarder
- Générer une clé ssh si ce n'est pas déja fait avec l'utilisateur qui va lancer le script de sauvegarde
- Créer un dépot sur l'UX de borgwarehouse (BWH) en ajoutant la clé publique
- clic sur la ptite icone en haut a gauche du nouvel objet backup sur BWH pour copier l'adresse ssh
- retourner sur le dossier de sauvegarde et initier le dépot en faisant : 

```
borg init -e repokey-blake2 <adresse ssh>
```

- générer et renseigner un mot de passe super super super fort et le stocker dans un coffre fort numérique. Garder aussi l'id du repo au cazou ( ex: c7a620ed )

- Backuper la PASSPHRASE au même endroit que la clé :
```
borg key export <adresse ssh> ./key && cat ./key && rm ./key
```


## Écrire un script de backup et le lancer régulièrement. 

Par exemple, pour Tibillet et une base postgres : https://github.com/TiBillet/Lespass/blob/PreProd/cron/saveDb.sh