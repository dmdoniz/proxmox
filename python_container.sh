#!/bin/bash

# ===== KONFIGURATION =====
#CTID=200                             # Container-ID
HOSTNAME="python"                    # Hostname des Containers
PASSWORD="dasistpython"              # Root-Passwort
STORAGE="local-lvm"                  # Speicher, z. B. local, local-lvm, etc.
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
DISK_SIZE="4G"                       # Speicherplatz
MEMORY="2048"                        # RAM in MB
CPUS=2                               # Anzahl vCPU
BRIDGE="vmbr0"                       # Netzwerk-Bridge
IP="dhcp"                            # IP-Adresse (oder statisch z. B. 192.168.1.100/24)
GATEWAY=""                           # Optional: Standard-Gateway
#PYTHON_VERSION="latest"              # oder eine feste Version wie 3.12.2
PYTHON_VERSION="3.12.3"              # oder eine feste Version wie 3.12.2

# ===== Container ID bestimmten
while true; do
  read -p "Bitte gib die gewünschte Container-ID ein: " CTID
  if pct status "$CTID" &>/dev/null; then
    echo "❌ Container-ID $CTID ist bereits vergeben. Bitte wähle eine andere."
  else
    break
  fi
done

# ===== TEMPLATE LADEN, FALLS NICHT VORHANDEN =====
if ! pveam list local | grep -q "$TEMPLATE"; then
  echo "🔽 Lade Ubuntu-Template herunter..."
  pveam update
  pveam download local $TEMPLATE
fi

# ===== LXC-CONTAINER ERSTELLEN =====
echo "📦 Erstelle LXC-Container $CTID..."
pct create $CTID local:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --storage $STORAGE \
  --rootfs local:4G
#  --rootfs ${STORAGE}:$DISK_SIZE \
  --memory $MEMORY \
  --cores $CPUS \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP${GATEWAY:+,gw=$GATEWAY} \
  --features nesting=1 \
  --unprivileged 1

# ===== STARTEN UND KONFIGURIEREN =====
echo "🚀 Starte Container..."
pct start $CTID
sleep 5

# ===== INSTALLIERE wichtige Pakete =====
apt install -y vim nano tree net-tools htop lsof iputils-ping

# ===== INSTALLIERE NEUESTE PYTHON-VERSION =====
echo "🐍 Installiere Python im Container..."
pct exec $CTID -- bash -c "
  apt update && apt install -y curl git build-essential libssl-dev zlib1g-dev \
    libncurses-dev libbz2-dev libreadline-dev libsqlite3-dev wget llvm \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

  curl https://pyenv.run | bash

  export PATH=\"/root/.pyenv/bin:\$PATH\"
  eval \"\$(pyenv init -)\"
  eval \"\$(pyenv virtualenv-init -)\"
  pyenv install $PYTHON_VERSION
  pyenv global $PYTHON_VERSION
  python --version
"

# ===== INSTALLIERE NEUESTE SAMBA-VERSION =====
echo "🐍 Installiere Samba im Container..."
pct exec $CTID -- bash -c "
  apt update
  apt install -y samba
	
  mkdir -p /srv/samba/share
  chmod 2770 /srv/samba/share
  chown nobody:nogroup /srv/samba/share

  if ! grep -q '^\[share\]' /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf <<EOF

  [share]
    path = /srv/samba/share
	browsable = yes
	writable = yes
	guest ok = yes
	read only = no
	create mask = 0660
	directory mask = 2770
EOF
	fi

  systemctl restart smbd || service smbd restart
"
	


echo "✅ LXC-Container $CTID für Python ist bereit!"
