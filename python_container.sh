#!/bin/bash

# ===== KONFIGURATION =====
HOSTNAME="python"                    # Hostname des Containers
PASSWORD="dasistpython"             # Root-Passwort
STORAGE1="local"
STORAGE2="local-lvm"                # Speicher, z. B. local, local-lvm, etc.
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
DISK_SIZE="2G"                      # Speicherplatz
MEMORY="2048"                       # RAM in MB
CPUS=2                              # Anzahl vCPU
BRIDGE="vmbr0"                      # Netzwerk-Bridge
IP="dhcp"                           # IP-Adresse oder statisch (z. B. 192.168.1.100/24)
GATEWAY=""                          # Optional: Gateway
PYTHON_VERSION="3.12.3"             # Python-Version via pyenv

# ===== Container ID bestimmen =====
while true; do
  read -p "Bitte gib die gewünschte Container-ID ein: " CTID
  if pct status "$CTID" &>/dev/null; then
    echo "❌ Container-ID $CTID ist bereits vergeben. Bitte wähle eine andere."
  else
    break
  fi
done

# ===== Template laden (falls nicht vorhanden) =====
if ! pveam list local | grep -q "$TEMPLATE"; then
  echo "🔽 Lade Ubuntu-Template herunter..."
  pveam update
  pveam download local $TEMPLATE
fi

# ===== LXC-Container erstellen =====
echo "📦 Erstelle LXC-Container $CTID..."
pct create $CTID local:vztmpl/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --storage $STORAGE1 \
  --rootfs ${STORAGE2}:subvol-${CTID}-disk-0,size=${DISK_SIZE}
  --memory $MEMORY \
  --cores $CPUS \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP${GATEWAY:+,gw=$GATEWAY} \
  --features nesting=1 \
  --unprivileged 1

# ===== Container starten =====
echo "🚀 Starte Container..."
pct start $CTID
sleep 5

# ===== Tools im Container installieren =====
echo "🧰 Installiere Standardpakete im Container..."
pct exec $CTID -- apt update
pct exec $CTID -- apt install -y vim nano tree net-tools htop lsof iputils-ping

# ===== Python installieren =====
echo "🐍 Installiere Python $PYTHON_VERSION im Container..."
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

# ===== Samba installieren und konfigurieren =====
echo "📁 Installiere und konfiguriere Samba im Container..."
pct exec $CTID -- bash -c "
  apt update && apt install -y samba

  mkdir -p /srv/samba/share
  chmod 2770 /srv/samba/share
  chown nobody:nogroup /srv/samba/share

  if ! grep -q '^\[share\]' /etc/samba/smb.conf; then
    echo '[share]' >> /etc/samba/smb.conf
    echo '  path = /srv/samba/share' >> /etc/samba/smb.conf
    echo '  browsable = yes' >> /etc/samba/smb.conf
    echo '  writable = yes' >> /etc/samba/smb.conf
    echo '  guest ok = yes' >> /etc/samba/smb.conf
    echo '  read only = no' >> /etc/samba/smb.conf
    echo '  create mask = 0660' >> /etc/samba/smb.conf
    echo '  directory mask = 2770' >> /etc/samba/smb.conf
  fi

  systemctl restart smbd || service smbd restart
"

echo "✅ LXC-Container $CTID mit Ubuntu, Python $PYTHON_VERSION und Samba ist fertig!"
