# Pipeline CI/CD — Zero to Deploy

Pipeline CI/CD complet pour une application Spring Boot : à chaque push sur `master`, le code est compilé, testé, analysé (sécurité), conteneurisé et déployé automatiquement sur un VPS distant. Une notification Slack résume le résultat de chaque étape.

---

## Table des matières

1. [Choix de l'outil CI/CD](#choix-de-loutil-cicd)
2. [Architecture du pipeline](#architecture-du-pipeline)
3. [Comment ça marche](#comment-ça-marche)
4. [Stack technique](#stack-technique)
5. [Structure du projet](#structure-du-projet)
6. [Prérequis](#prérequis)
7. [Configuration des secrets GitHub](#configuration-des-secrets-github)
8. [Préparation du serveur VPS](#préparation-du-serveur-vps)
9. [Lancement du pipeline](#lancement-du-pipeline)
10. [Vérification du déploiement](#vérification-du-déploiement)

---

## Choix de l'outil CI/CD

Le sujet laisse le choix de l'outil CI/CD (Jenkins, GitLab CI, GitHub Actions…). **GitHub Actions** a été retenu pour les raisons suivantes :

| Critère | Jenkins | GitHub Actions |
|---|---|---|
| **Infrastructure** | Serveur Jenkins à installer, maintenir et sécuriser soi-même | SaaS — zéro serveur à gérer, focus uniquement sur le pipeline |
| **Plugins** | « Enfer des plugins » : incompatibilités fréquentes, failles de sécurité, mises à jour manuelles | Actions versionnées et isolées, écosystème stable via le Marketplace |
| **Intégration Git** | Webhook externe à configurer entre Jenkins et GitHub | Natif — le pipeline connaît les commits, branches et PR sans configuration |
| **Scalabilité** | Agents/nœuds à provisionner manuellement | Runners hébergés auto-scalables (builds parallèles sans effort) |
| **Coût** | Gratuit mais coût du serveur + maintenance | Gratuit pour les dépôts publics, 2 000 min/mois pour les dépôts privés |
| **Configuration** | Jenkinsfile + interface web | Fichier YAML unique dans le dépôt (`.github/workflows/`) |

> **En résumé :** GitHub Actions élimine la charge opérationnelle liée à Jenkins (serveur, plugins, webhooks) tout en offrant une intégration native avec GitHub et une scalabilité automatique.

---

## Architecture du pipeline

Le pipeline suit une approche **DevSecOps** — la sécurité est intégrée directement dans la chaîne CI/CD, pas ajoutée après coup. Il se déclenche à chaque push sur `master` et exécute 6 étapes séquentielles :

```
Push sur master
    │
    ▼
┌──────────────────┐
│ 1. Build & Test  │  Compilation Maven + tests unitaires (JUnit)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 2. Analyse code  │  Scan vulnérabilités : Trivy (CVE) + Snyk (dépendances)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 3. Dockerisation │  Build multi-stage (Maven → JRE Alpine) + scan image Snyk
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 4. Registry      │  Push vers Docker Hub (tag SHA + latest)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 5. Déploiement   │  SSH → docker compose pull && up -d
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ 6. Notification  │  Rapport complet via Slack
└──────────────────┘
```

<!-- Capture d'écran : vue d'ensemble du pipeline dans GitHub Actions -->
<!-- ![Pipeline](docs/screenshots/pipeline-overview.png) -->

---

## Comment ça marche

Voici ce qui se passe concrètement à chaque étape du pipeline :

### 1. Build & Test

Le runner GitHub télécharge le code, installe JDK 17, et exécute `mvn clean verify`. Maven compile les sources, lance les tests unitaires JUnit et produit un `.jar` exécutable. Si un test échoue, le pipeline s'arrête immédiatement.

### 2. Analyse de code (DevSecOps)

Deux scans de sécurité sont exécutés en parallèle :
- **Trivy** scanne les fichiers sources pour détecter les CVE connues (vulnérabilités CRITICAL et HIGH). Le résultat inclut les identifiants CVE et les packages affectés.
- **Snyk** analyse les dépendances Maven pour identifier les librairies vulnérables.

> Ces scans ne bloquent pas le pipeline (`continue-on-error: true`) mais les résultats sont remontés dans la notification Slack pour visibilité.

### 3. Dockerisation

L'image Docker est construite en **multi-stage** :
1. **Étape build** : Maven compile le `.jar` dans une image Alpine Maven (~400 Mo)
2. **Étape finale** : seul le `.jar` est copié dans une image JRE Alpine légère (~80 Mo)

L'image tourne avec un utilisateur non-root (`afrikpay`) pour la sécurité. Une fois construite, Snyk scanne l'image Docker pour détecter les vulnérabilités de l'OS et des couches.

### 4. Registry

L'image est poussée sur Docker Hub avec deux tags :
- `latest` — pour le déploiement courant
- `<sha-du-commit>` — pour la traçabilité et les rollbacks

### 5. Déploiement

Le pipeline se connecte au VPS via SSH et exécute :
```bash
cd /home/cicd/hello-world    # DEPLOY_PATH sur le serveur
docker compose pull           # télécharge la nouvelle image depuis Docker Hub
docker compose up -d          # relance le conteneur avec la nouvelle version
```

C'est possible parce que le serveur contient déjà un fichier `docker-compose.yml` et un fichier `.env` (voir [Préparation du serveur VPS](#préparation-du-serveur-vps)).

### 6. Notification

À la fin du pipeline (succès ou échec), un message Slack est envoyé avec :
- Le statut de chaque étape (✅ / ❌ / ⏭️)
- Les CVE détectées par Trivy (top 3 + compteur)
- Le nombre de vulnérabilités Snyk (code + image)
- Le lien vers le run GitHub Actions

<!-- Capture d'écran : notification Slack -->
<!-- ![Notification Slack](docs/screenshots/slack-notification.png) -->

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
│       └── ci-cd.yml              # Pipeline CI/CD complet
├── src/
│   ├── main/
│   │   ├── java/.../              # Code source Java (HelloController)
│   │   └── resources/
│   │       └── application.yml    # Configuration Spring Boot
│   └── test/
│       └── java/.../              # Tests unitaires (JUnit)
├── .dockerignore                  # Fichiers exclus du contexte Docker
├── .gitignore
├── Dockerfile                     # Image Docker multi-stage
├── pom.xml                        # Dépendances Maven
├── setup-server.sh                # Script d'installation automatique du VPS
└── README.md
```

> **Note :** Les fichiers `docker-compose.yml` et `.env` ne sont pas dans le dépôt. Ils sont créés directement sur le serveur VPS lors de la préparation (voir section ci-dessous).

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
| `IMAGE_NAME`        | Nom de l'image Docker (ex: `hello-world`)           |
| `VPS_HOST`          | Adresse IP du serveur                               |
| `VPS_USER`          | Utilisateur SSH pour le déploiement (ex: `cicd`)    |
| `VPS_SSH_KEY`       | Clé privée SSH (contenu complet, voir section VPS)  |
| `DEPLOY_PATH`       | Chemin sur le serveur (ex: `/home/cicd/hello-world`)|
| `SLACK_WEBHOOK_URL` | URL du webhook Slack                                |
| `SNYK_TOKEN`        | Token API Snyk (snyk.io → Account Settings)         |

<!-- Capture d'écran : page des secrets GitHub -->
<!-- ![Secrets GitHub](docs/screenshots/github-secrets.png) -->

---

## Préparation du serveur VPS

### Étape 1 : Exécuter le script d'installation

Le script `setup-server.sh` automatise entièrement la configuration du serveur :

- Mise à jour du système
- Installation de Docker et Docker Compose
- Création de l'utilisateur `cicd` avec accès Docker
- Génération des clés SSH (ed25519)
- Configuration du firewall (UFW) — ports 22 et 8080
- Durcissement SSH (désactivation root login, limitation des tentatives)

Se connecter au serveur en root et lancer :

```bash
# Copier le script sur le serveur
scp setup-server.sh root@<ip-du-serveur>:/tmp/

# Se connecter au serveur
ssh root@<ip-du-serveur>

# Lancer le script
chmod +x /tmp/setup-server.sh
/tmp/setup-server.sh
```

À la fin de l'exécution, le script affiche la **clé privée SSH**. Copier son contenu dans le secret GitHub `VPS_SSH_KEY`.

<!-- Capture d'écran : exécution du script sur le VPS -->
<!-- ![Setup serveur](docs/screenshots/setup-server.png) -->

### Étape 2 : Créer le fichier `docker-compose.yml` sur le serveur

Ce fichier indique à Docker comment lancer le conteneur. Il est créé directement sur le VPS dans le répertoire de déploiement (`/home/cicd/hello-world`) :

```bash
ssh cicd@<ip-du-serveur>
nano /home/cicd/hello-world/docker-compose.yml
```

Contenu :

```yaml
services:
  app:
    image: ${IMAGE_NAME}:latest
    container_name: ${CONTAINER_NAME}
    ports:
      - "${SERVER_PORT}:${CONTAINER_PORT}"
    restart: unless-stopped
```

**Pourquoi ce fichier n'est pas dans le dépôt ?** Parce qu'il contient des variables d'environnement propres au serveur. Le pipeline exécute `docker compose pull && up -d` sur le serveur, qui lit ce fichier localement.

### Étape 3 : Créer le fichier `.env` sur le serveur

Le fichier `.env` fournit les valeurs des variables utilisées par `docker-compose.yml` :

```bash
nano /home/cicd/hello-world/.env
```

Contenu :

```env
IMAGE_NAME=<votre-user-dockerhub>/<nom-image>
CONTAINER_NAME=hello-world
SERVER_PORT=8080
CONTAINER_PORT=8080
```

| Variable         | Description                                           |
|------------------|-------------------------------------------------------|
| `IMAGE_NAME`     | Nom complet de l'image Docker Hub (ex: `bigzaza/hello-world`) |
| `CONTAINER_NAME` | Nom du conteneur Docker sur le serveur                |
| `SERVER_PORT`    | Port exposé sur le serveur (accessible depuis l'extérieur) |
| `CONTAINER_PORT` | Port interne du conteneur (celui de Spring Boot)      |

<!-- Capture d'écran : fichiers sur le serveur (ls -la) -->
<!-- ![Fichiers serveur](docs/screenshots/server-files.png) -->

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

<!-- Capture d'écran : détail d'un job réussi -->
<!-- ![Job réussi](docs/screenshots/job-success.png) -->

Une fois le pipeline terminé, **vérifier le statut sur Slack** : la notification indique le résultat de chaque étape, les CVE détectées et un lien direct vers le run.

<!-- Capture d'écran : notification Slack finale -->
<!-- ![Notification Slack](docs/screenshots/slack-final.png) -->

---

## Vérification du déploiement

Après un pipeline réussi (toutes les étapes ✅ sur Slack), vérifier que l'application tourne sur le serveur.

### 1. Vérifier que le conteneur est actif

```bash
ssh cicd@<ip-du-serveur>
docker ps
```

Le conteneur `hello-world` doit apparaître avec le statut `Up` :

<img width="1919" height="311" alt="image" src="https://github.com/user-attachments/assets/57591097-855f-4c74-abb9-8ef1ad8a9dfc" />


### 2. Vérifier les logs du conteneur

```bash
docker logs hello-world
```

On doit voir le démarrage de Spring Boot sans erreur.

### 3. Tester l'application

Depuis n'importe quelle machine :

```bash
curl http://<ip-du-serveur>:8080/
```

Réponse attendue :

```
Hello World!
```

<!-- Capture d'écran : résultat du curl -->
<!-- ![Test curl](docs/screenshots/curl-test.png) -->

---

## Auteur

Projet réalisé dans le cadre du test technique Lead DevOps.
