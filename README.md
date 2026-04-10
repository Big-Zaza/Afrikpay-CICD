# Pipeline CI/CD — Zero to Deploy

Pipeline CI/CD complet pour une application Spring Boot : à chaque push sur `master`, le code est compilé, testé, analysé, conteneurisé et déployé automatiquement sur un VPS distant.

---

## Table des matières

1. [Architecture du pipeline](#architecture-du-pipeline)
2. [Stack technique](#stack-technique)
3. [Structure du projet](#structure-du-projet)
4. [Prérequis](#prérequis)
5. [Configuration des secrets GitHub](#configuration-des-secrets-github)
6. [Préparation du serveur VPS](#préparation-du-serveur-vps)
7. [Lancement du pipeline](#lancement-du-pipeline)
8. [Vérification du déploiement](#vérification-du-déploiement)

---

## Architecture du pipeline

Le pipeline se déclenche à chaque push sur la branche `master` et exécute 6 étapes dans l'ordre :

```
Push sur master
    │
    ▼
┌──────────────────┐
│ 1. Build & Test  │  Compilation Maven + tests unitaires
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 2. Analyse code  │  Scan de vulnérabilités (Trivy + Snyk)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 3. Dockerisation │  Build de l'image Docker (multi-stage)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 4. Registry      │  Push de l'image sur Docker Hub
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 5. Déploiement   │  SSH → docker compose pull + up
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 6. Notification  │  Statut de chaque étape via Slack
└──────────────────┘
```

<!-- Capture d'écran : vue d'ensemble du pipeline dans GitHub Actions -->
<!-- ![Pipeline](docs/screenshots/pipeline-overview.png) -->

---

## Stack technique

| Composant          | Technologie                                       |
|--------------------|---------------------------------------------------|
| Application        | Spring Boot 3.2 / Java 17                         |
| CI/CD              | GitHub Actions                                     |
| Conteneurisation   | Docker (multi-stage build)                         |
| Registry           | Docker Hub                                         |
| Analyse de code    | Trivy (code source) + Snyk (dépendances + image)  |
| Déploiement        | SSH vers VPS Linux + Docker Compose                |
| Notification       | Slack (webhook)                                    |

---

## Structure du projet

```
.
├── .github/
│   └── workflows/
│       └── ci-cd.yml              # Pipeline CI/CD
├── src/
│   ├── main/
│   │   ├── java/.../              # Code source Java
│   │   └── resources/
│   │       └── application.yml    # Configuration Spring Boot
│   └── test/
│       └── java/.../              # Tests unitaires
├── .dockerignore
├── .env.example                   # Modèle de variables d'environnement
├── .gitignore
├── docker-compose.yml             # Déploiement sur le serveur
├── Dockerfile                     # Image Docker multi-stage
├── pom.xml                        # Dépendances Maven
├── setup-server.sh                # Script d'installation du serveur
└── README.md
```

---

## Prérequis

**En local (pour développer) :**
- Java 17+
- Maven 3.9+
- Git

**Sur le serveur VPS :**
- Ubuntu/Debian
- Docker et Docker Compose
- Utilisateur de déploiement avec accès Docker
- Firewall (UFW) configuré
- Clés SSH générées

> Tout cela est installé automatiquement par le script `setup-server.sh` (voir section suivante).

**Comptes nécessaires :**
- [GitHub](https://github.com) — dépôt + GitHub Actions
- [Docker Hub](https://hub.docker.com) — registre d'images
- [Slack](https://api.slack.com/messaging/webhooks) — webhook pour les notifications
- [Snyk](https://snyk.io) (gratuit) — scan de vulnérabilités

---

## Configuration des secrets GitHub

Aller dans le dépôt GitHub → **Settings** → **Secrets and variables** → **Actions** et ajouter :

| Secret              | Description                                         |
|---------------------|-----------------------------------------------------|
| `DOCKER_USERNAME`   | Nom d'utilisateur Docker Hub                        |
| `DOCKER_PASSWORD`   | Token d'accès Docker Hub                            |
| `IMAGE_NAME`        | Nom de l'image Docker (ex: hello-world)             |
| `VPS_HOST`          | Adresse IP du serveur                               |
| `VPS_USER`          | Utilisateur SSH pour le déploiement                  |
| `VPS_SSH_KEY`       | Clé privée SSH (contenu complet, voir section VPS)  |
| `DEPLOY_PATH`       | Chemin du répertoire de déploiement sur le serveur   |
| `SLACK_WEBHOOK_URL` | URL du webhook Slack                                |
| `SNYK_TOKEN`        | Token API Snyk (snyk.io → Account Settings)         |

<!-- Capture d'écran : page des secrets GitHub -->
<!-- ![Secrets GitHub](docs/screenshots/github-secrets.png) -->

---

## Préparation du serveur VPS

Le script `setup-server.sh` automatise entièrement la configuration du serveur :

- Mise à jour du système
- Installation de Docker et Docker Compose
- Création de l'utilisateur de déploiement avec accès Docker
- Génération des clés SSH
- Configuration du firewall (UFW) — ports SSH et 8080
- Durcissement de la configuration SSH

### Exécution du script

Se connecter au serveur en root (ou avec sudo) et lancer :

```bash
# Copier le script sur le serveur
scp setup-server.sh root@ip-du-serveur:/tmp/

# Se connecter au serveur
ssh root@ip-du-serveur

# Lancer le script
chmod +x /tmp/setup-server.sh
/tmp/setup-server.sh
```

À la fin de l'exécution, le script affiche la **clé privée SSH** à copier dans le secret GitHub `VPS_SSH_KEY`.

<!-- Capture d'écran : exécution du script sur le VPS -->
<!-- ![Setup serveur](docs/screenshots/setup-server.png) -->

### Fichiers de déploiement

Après l'exécution du script, copier les fichiers nécessaires sur le serveur :

```bash
# Depuis votre machine locale
scp docker-compose.yml <user>@<ip-du-serveur>:<chemin-deploiement>/
```

Créer le fichier `.env` sur le serveur :

```bash
ssh <user>@<ip-du-serveur>
nano <chemin-deploiement>/.env
```

Contenu :

```env
IMAGE_NAME=<votre-user-dockerhub>/<nom-image>
CONTAINER_NAME=<nom-conteneur>
SERVER_PORT=8080
CONTAINER_PORT=8080
```

---

## Lancement du pipeline

Le pipeline se déclenche automatiquement à chaque push sur `master` :

```bash
git add .
git commit -m "feat: déploiement initial"
git push origin master
```

Suivre l'exécution dans l'onglet **Actions** du dépôt GitHub.

<!-- Capture d'écran : pipeline en cours d'exécution -->
<!-- ![Pipeline en cours](docs/screenshots/pipeline-running.png) -->

<!-- Capture d'écran : détail d'un job -->
<!-- ![Job réussi](docs/screenshots/job-success.png) -->

---

## Vérification du déploiement

Une fois le pipeline terminé, vérifier que l'application répond :

```bash
curl http://<ip-du-serveur>:<port>/
```

Réponse attendue :

```
Hello World!
```

Vérifier l'état du conteneur sur le serveur :

```bash
docker ps
docker logs <nom-conteneur>
```

<!-- Capture d'écran : résultat du curl et docker ps -->
<!-- ![Vérification](docs/screenshots/deploy-check.png) -->

---

## Auteur

Projet réalisé dans le cadre du test technique Lead DevOps.
