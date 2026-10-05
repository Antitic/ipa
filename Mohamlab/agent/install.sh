#!/usr/bin/env bash
# Installe (ou met à jour) mlab-agent sur le Homelab. À lancer en root.
set -euo pipefail
cd "$(dirname "$0")"
apt-get install -y python3-psutil >/dev/null 2>&1 || true
install -d /opt/mlab-agent /etc/mlab-agent
install -m 755 mlab_agent.py /opt/mlab-agent/mlab_agent.py
if [ ! -s /etc/mlab-agent/token ]; then
  python3 -c "import secrets; print(secrets.token_urlsafe(32))" > /etc/mlab-agent/token
  chmod 600 /etc/mlab-agent/token
fi
cat > /etc/systemd/system/mlab-agent.service <<'UNIT'
[Unit]
Description=Mlab Agent — l'API de supervision pour l'app iPhone
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/mlab-agent/mlab_agent.py
Restart=on-failure
RestartSec=5
MemoryMax=160M
Nice=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now mlab-agent
systemctl restart mlab-agent
echo "✓ mlab-agent actif — jeton : $(cat /etc/mlab-agent/token)"
