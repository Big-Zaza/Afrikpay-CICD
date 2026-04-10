#!/bin/bash
set -e

# ==========================
# Script de configuration du serveur VPS
# Installe Docker, configure le firewall, durcit SSH
# et prépare l'environnement de déploiement
# ==========================

# --- Configuration ---
APP_USER="cicd"
APP_NAME="hello-world"
APP_DIR="/home/$APP_USER/$APP_NAME"
APP_PORT=8080
SSH_PORT=22

echo ""
echo "=== Configuration du serveur VPS ==="
echo ""

# --- Mise à jour du système ---
echo "[1/6] Mise à jour du système..."
apt-get update -y && apt-get upgrade -y

# --- Installation de Docker ---
echo "[2/6] Installation de Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    echo "Docker installé."
else
    echo "Docker déjà installé."
fi

# --- Création de l'utilisateur cicd ---
echo "[3/6] Création de l'utilisateur $APP_USER..."
if ! id "$APP_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$APP_USER"
    echo "Utilisateur $APP_USER créé."
else
    echo "Utilisateur $APP_USER existe déjà."
fi
usermod -aG docker "$APP_USER"

# --- Génération des clés SSH pour cicd ---
echo "[4/6] Configuration SSH pour $APP_USER..."
SSH_DIR="/home/$APP_USER/.ssh"
if [ ! -f "$SSH_DIR/id_ed25519" ]; then
    mkdir -p "$SSH_DIR"
    ssh-keygen -t ed25519 -C "cicd-deploy" -f "$SSH_DIR/id_ed25519" -N ""
    cat "$SSH_DIR/id_ed25519.pub" >> "$SSH_DIR/authorized_keys"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys" "$SSH_DIR/id_ed25519"
    chown -R "$APP_USER:$APP_USER" "$SSH_DIR"
    echo "Clés SSH générées."
    echo ""
    echo ">>> CLÉ PRIVÉE (à copier dans le secret GitHub VPS_SSH_KEY) :"
    echo ">>> ATTENTION : copiez-la maintenant, elle ne sera plus affichée."
    echo ""
    cat "$SSH_DIR/id_ed25519"
    echo ""
else
    echo "Clés SSH déjà configurées."
fi

# --- Configuration du firewall (UFW) ---
echo "[5/6] Configuration du firewall..."
if ! command -v ufw &>/dev/null; then
    apt-get install ufw -y
fi
ufw allow "$SSH_PORT/tcp"
ufw allow "$APP_PORT/tcp"
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
echo "Firewall configuré."

# --- Durcissement SSH ---
echo "[6/6] Durcissement SSH..."
configure_ssh() {
    KEY="$1"; VALUE="$2"
    if grep -q "^$KEY" /etc/ssh/sshd_config; then
        sed -i "s|^$KEY.*|$KEY $VALUE|" /etc/ssh/sshd_config
    else
        echo "$KEY $VALUE" >> /etc/ssh/sshd_config
    fi
}
configure_ssh "PermitRootLogin" "no"
configure_ssh "MaxAuthTries" "3"
configure_ssh "ClientAliveInterval" "300"
configure_ssh "ClientAliveCountMax" "2"
systemctl restart ssh
echo "SSH durci."

# --- Préparation du répertoire de déploiement ---
echo ""
echo "=== Préparation du répertoire $APP_DIR ==="
su - "$APP_USER" -c "mkdir -p $APP_DIR"
echo "Répertoire créé."

echo ""
echo "=== Configuration terminée ==="
echo ""
echo "Prochaines étapes :"
echo "  1. Copier docker-compose.yml dans $APP_DIR"
echo "  2. Créer le fichier .env dans $APP_DIR"
echo "  3. Ajouter la clé privée ci-dessus dans le secret GitHub VPS_SSH_KEY"
echo ""
