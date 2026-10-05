#!/usr/bin/env python3
"""
mlab-agent — l'API de supervision du Homelab pour l'app iOS « Mohamlab ».

Aucune dépendance hors psutil. Écoute sur 0.0.0.0:8787 mais n'accepte que
Tailscale (100.64.0.0/10), le réseau local et localhost, et exige un jeton.

Endpoints (tous en GET sauf mention) :
  /api/ping                          → vivant ?
  /api/overview                      → ressources, températures, réseau, alertes
  /api/history                       → 1 h d'historique CPU / RAM / réseau / temp
  /api/services                      → services systemd utiles, état, mémoire, ports
  /api/logs?hours=12&level=all&unit= → journal simplifié et regroupé
  POST /api/services/<unit>/restart  → redémarre un service de la liste
"""
import hmac
import ipaddress
import json
import os
import platform
import re
import socket
import subprocess
import threading
import time
from collections import deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

import psutil

VERSION = "1.0"
BIND = os.environ.get("MLAB_BIND", "0.0.0.0")
PORT = int(os.environ.get("MLAB_PORT", "8787"))
TOKEN_FILE = os.environ.get("MLAB_TOKEN_FILE", "/etc/mlab-agent/token")
with open(TOKEN_FILE) as f:
    TOKEN = f.read().strip()

ALLOWED_NETS = [ipaddress.ip_network(n) for n in (
    "100.64.0.0/10", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12",
    "127.0.0.0/8", "fd7a:115c:a1e0::/48", "::1/128")]

# Services « du système » qu'on veut voir même s'ils viennent d'un paquet.
NOTABLE = {
    "jellyfin", "apache2", "cloudflared", "tailscaled", "ssh", "maddy",
    "valkey-server", "qbittorrent-nox", "prowlarr", "cross-seed", "searxng",
    "uwsgi", "v2ray", "cron", "smartmontools", "NetworkManager", "atop",
}
# Jamais redémarrables depuis l'app : ça couperait la connexion.
NO_RESTART = {"tailscaled", "mlab-agent", "ssh", "NetworkManager", "dbus", "systemd-journald"}

CATEGORIES = [
    ("media",   ("jellyfin", "qbit", "qbt", "prowlarr", "cross-seed", "stream", "films", "cam", "dl-")),
    ("reseau",  ("tailscale", "cloudflared", "v2ray", "tor", "ssh", "networkmanager", "vpn", "wpa", "avahi", "modem")),
    ("mail",    ("maddy", "mail")),
    ("donnees", ("valkey", "redis", "postgres", "mysql", "mariadb", "atop", "smart")),
    ("bot",     ("bot", "crise")),
    ("web",     ("apache", "nginx", "uwsgi", "searx", "dipherant", "kloz", "kontakt", "storia", "lyst",
                 "brandix", "angl", "kinet", "pin", "phriend", "boucan", "calendrier", "shell", "kru")),
]


def category_for(name: str) -> str:
    n = name.lower()
    for cat, keys in CATEGORIES:
        if any(re.search(r"(^|[-_])" + re.escape(k.rstrip("-")), n) for k in keys):
            return cat
    return "systeme"


# ───────────────────────────── échantillonnage ─────────────────────────────

class Sampler:
    """Mesure en continu ce qui demande deux points (CPU, débits réseau)."""

    def __init__(self):
        self.lock = threading.Lock()
        self.cpu = 0.0
        self.per_core = []
        self.rx_rate = 0.0
        self.tx_rate = 0.0
        self.disk_read_rate = 0.0
        self.disk_write_rate = 0.0
        self.top_cpu = []
        self.history = deque(maxlen=240)  # 240 × 15 s = 1 h
        self._last_net = psutil.net_io_counters()
        self._last_disk = psutil.disk_io_counters()
        self._last_t = time.monotonic()
        self._last_hist = 0.0
        psutil.cpu_percent(percpu=True)
        for p in psutil.process_iter():
            try:
                p.cpu_percent(None)
            except psutil.Error:
                pass

    def run(self):
        while True:
            time.sleep(2)
            try:
                self.tick()
            except Exception as e:  # ne jamais tuer le thread
                print("sampler:", e, flush=True)

    def tick(self):
        now = time.monotonic()
        dt = max(now - self._last_t, 0.001)
        per = psutil.cpu_percent(percpu=True)
        net = psutil.net_io_counters()
        disk = psutil.disk_io_counters()
        rx = (net.bytes_recv - self._last_net.bytes_recv) / dt
        tx = (net.bytes_sent - self._last_net.bytes_sent) / dt
        dr = (disk.read_bytes - self._last_disk.read_bytes) / dt if disk else 0
        dw = (disk.write_bytes - self._last_disk.write_bytes) / dt if disk else 0
        self._last_net, self._last_disk, self._last_t = net, disk, now

        procs = []
        for p in psutil.process_iter(["name", "memory_info", "username"]):
            try:
                c = p.cpu_percent(None)
                procs.append({
                    "pid": p.pid,
                    "name": p.info["name"] or "?",
                    "user": p.info["username"] or "?",
                    "cpu": round(c, 1),
                    "memory": p.info["memory_info"].rss if p.info["memory_info"] else 0,
                })
            except psutil.Error:
                pass
        procs.sort(key=lambda x: x["cpu"], reverse=True)

        with self.lock:
            self.per_core = per
            self.cpu = sum(per) / len(per) if per else 0.0
            self.rx_rate, self.tx_rate = max(rx, 0), max(tx, 0)
            self.disk_read_rate, self.disk_write_rate = max(dr, 0), max(dw, 0)
            self.top_cpu = procs[:6]
            if now - self._last_hist >= 15 or not self.history:
                self._last_hist = now
                self.history.append({
                    "t": int(time.time()),
                    "cpu": round(self.cpu, 1),
                    "mem": round(psutil.virtual_memory().percent, 1),
                    "rx": int(self.rx_rate),
                    "tx": int(self.tx_rate),
                    "temp": cpu_temperature(),
                })


SAMPLER = None


def cpu_temperature():
    try:
        temps = psutil.sensors_temperatures()
    except Exception:
        return None
    for key in ("coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz"):
        entries = temps.get(key)
        if entries:
            pkg = [e for e in entries if (e.label or "").lower().startswith("package")]
            return round((pkg[0] if pkg else max(entries, key=lambda e: e.current)).current, 1)
    return None


# ───────────────────────────── vue d'ensemble ─────────────────────────────

_ALERTS_CACHE = {"t": 0, "v": {"errors": 0, "warnings": 0}}


def alert_counts():
    if time.time() - _ALERTS_CACHE["t"] < 60:
        return _ALERTS_CACHE["v"]
    c = logs(24, "warning")["counts"]
    errors, warnings = c["error"], c["warning"]
    _ALERTS_CACHE.update(t=time.time(), v={"errors": errors, "warnings": warnings})
    return _ALERTS_CACHE["v"]


def overview():
    vm = psutil.virtual_memory()
    sw = psutil.swap_memory()
    load = os.getloadavg()
    boot = psutil.boot_time()

    disks, seen = [], set()
    for p in psutil.disk_partitions(all=False):
        if p.device in seen or p.fstype in ("squashfs", "overlay", "vfat") or p.mountpoint.startswith("/snap"):
            continue
        seen.add(p.device)
        try:
            u = psutil.disk_usage(p.mountpoint)
        except OSError:
            continue
        disks.append({"mount": p.mountpoint, "device": p.device, "fs": p.fstype,
                      "total": u.total, "used": u.used, "free": u.free, "percent": u.percent})

    fans = []
    try:
        for chip, entries in (psutil.sensors_fans() or {}).items():
            for e in entries:
                fans.append({"label": e.label or chip, "rpm": e.current})
    except Exception:
        pass

    sensors = []
    try:
        for chip, entries in (psutil.sensors_temperatures() or {}).items():
            for e in entries:
                sensors.append({"chip": chip, "label": e.label or chip, "current": e.current,
                                "high": e.high, "critical": e.critical})
    except Exception:
        pass

    battery = None
    try:
        b = psutil.sensors_battery()
        if b:
            battery = {"percent": round(b.percent, 1), "plugged": bool(b.power_plugged)}
    except Exception:
        pass

    addrs = []
    for iface, lst in psutil.net_if_addrs().items():
        if iface in ("lo",) or iface.startswith(("docker", "veth", "br-")):
            continue
        for a in lst:
            if a.family == socket.AF_INET:
                addrs.append({"iface": iface, "ip": a.address})

    with SAMPLER.lock:
        cpu, per_core = SAMPLER.cpu, list(SAMPLER.per_core)
        rx, tx = SAMPLER.rx_rate, SAMPLER.tx_rate
        dr, dw = SAMPLER.disk_read_rate, SAMPLER.disk_write_rate
        top_cpu = list(SAMPLER.top_cpu)

    top_mem = []
    for p in psutil.process_iter(["name", "memory_info"]):
        try:
            top_mem.append({"pid": p.pid, "name": p.info["name"] or "?",
                            "memory": p.info["memory_info"].rss if p.info["memory_info"] else 0})
        except psutil.Error:
            pass
    top_mem.sort(key=lambda x: x["memory"], reverse=True)

    svc = services()
    return {
        "hostname": socket.gethostname(),
        "os": _os_name(),
        "kernel": platform.release(),
        "agentVersion": VERSION,
        "time": int(time.time()),
        "uptime": int(time.time() - boot),
        "cpu": {"percent": round(cpu, 1), "cores": [round(c, 1) for c in per_core],
                "count": psutil.cpu_count(), "load": [round(x, 2) for x in load],
                "frequency": round(psutil.cpu_freq().current) if psutil.cpu_freq() else None},
        "memory": {"total": vm.total, "used": vm.total - vm.available, "available": vm.available,
                   "cached": getattr(vm, "cached", 0) + getattr(vm, "buffers", 0), "percent": vm.percent},
        "swap": {"total": sw.total, "used": sw.used, "percent": sw.percent},
        "disks": disks,
        "diskIO": {"read": int(dr), "write": int(dw)},
        "network": {"rx": int(rx), "tx": int(tx), "addresses": addrs},
        "temperature": cpu_temperature(),
        "sensors": sensors,
        "fans": fans,
        "battery": battery,
        "processes": len(psutil.pids()),
        "topCPU": top_cpu[:5],
        "topMemory": top_mem[:5],
        "services": {"total": len(svc), "running": sum(1 for s in svc if s["state"] == "running"),
                     "failed": sum(1 for s in svc if s["state"] == "failed")},
        "alerts": alert_counts(),
    }


def _os_name():
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return platform.system()


# ───────────────────────────── services ─────────────────────────────

PROPS = ["Id", "Description", "ActiveState", "SubState", "UnitFileState", "ActiveEnterTimestampMonotonic",
         "MemoryCurrent", "MemoryMax", "CPUUsageNSec", "NRestarts", "MainPID", "FragmentPath", "ControlGroup"]
_SVC_CACHE = {"t": 0, "v": []}
DESCRIPTIONS = {}


def _int(v):
    try:
        n = int(v)
        return None if n >= 2 ** 63 else n
    except (TypeError, ValueError):
        return None


def candidate_units():
    units = set()
    d = "/etc/systemd/system"
    for name in os.listdir(d):
        p = os.path.join(d, name)
        if name.endswith(".service") and os.path.isfile(p) and not os.path.islink(p) and "@" not in name:
            units.add(name)
    units |= {n + ".service" for n in NOTABLE}
    try:
        out = subprocess.run(["systemctl", "list-units", "--failed", "--type=service", "--no-legend",
                              "--plain", "--no-pager"], capture_output=True, text=True, timeout=10).stdout
        for line in out.splitlines():
            if line.strip():
                units.add(line.split()[0])
    except Exception:
        pass
    return sorted(units)


def listening_ports():
    ports = {}
    try:
        for c in psutil.net_connections(kind="inet"):
            if c.status == psutil.CONN_LISTEN and c.pid:
                ports.setdefault(c.pid, set()).add(c.laddr.port)
    except Exception:
        pass
    return ports


def split_desc(desc):
    for sep in (" — ", " | ", " - ", " – "):
        if sep in desc:
            a, _, b = desc.partition(sep)
            return a.strip(), b.strip()
    return desc.strip(), ""


def services():
    if time.time() - _SVC_CACHE["t"] < 3:
        return _SVC_CACHE["v"]
    units = candidate_units()
    out = subprocess.run(["systemctl", "show", "--no-pager", "-p", ",".join(PROPS), *units],
                         capture_output=True, text=True, timeout=15).stdout
    ports_by_pid = listening_ports()
    mono_now_us = time.monotonic() * 1_000_000
    result = []
    for block in out.strip().split("\n\n"):
        d = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if not d.get("Id") or d.get("FragmentPath", "") == "" and d.get("ActiveState") == "inactive":
            continue  # unité inexistante
        state = d.get("ActiveState", "unknown")
        enabled = d.get("UnitFileState", "")
        if state == "inactive" and enabled not in ("enabled", "static"):
            continue  # service retiré / désactivé : on n'encombre pas
        name = d["Id"].removesuffix(".service")
        desc = d.get("Description", name)
        DESCRIPTIONS[d["Id"]] = desc
        since = _int(d.get("ActiveEnterTimestampMonotonic"))
        uptime = int((mono_now_us - since) / 1e6) if since and state == "active" else None
        # PIDs du cgroup → ports d'écoute
        pids = set()
        cg = d.get("ControlGroup", "")
        if cg:
            try:
                with open(f"/sys/fs/cgroup{cg}/cgroup.procs") as f:
                    pids = {int(x) for x in f.read().split()}
            except OSError:
                pass
        ports = sorted({p for pid in pids for p in ports_by_pid.get(pid, ())})
        sub = d.get("SubState", "")
        if state == "active" and sub in ("running", "exited", "listening", "waiting"):
            simple = "running" if sub != "exited" else "done"
        elif state == "failed":
            simple = "failed"
        elif state in ("activating", "deactivating", "reloading"):
            simple = "starting"
        else:
            simple = "stopped"
        title, subtitle = split_desc(desc)
        result.append({
            "id": d["Id"],
            "name": name,
            "title": title.strip() or name,
            "subtitle": subtitle.strip(),
            "description": desc,
            "state": simple,
            "activeState": state,
            "subState": sub,
            "enabled": enabled == "enabled",
            "uptime": uptime,
            "memory": _int(d.get("MemoryCurrent")),
            "memoryMax": _int(d.get("MemoryMax")),
            "cpuSeconds": round(_int(d.get("CPUUsageNSec")) / 1e9, 1) if _int(d.get("CPUUsageNSec")) else None,
            "restarts": _int(d.get("NRestarts")) or 0,
            "pid": _int(d.get("MainPID")) or None,
            "ports": ports,
            "category": category_for(name),
            "custom": d.get("FragmentPath", "").startswith("/etc/systemd/system/"),
            "canRestart": name not in NO_RESTART,
        })
    order = {"failed": 0, "starting": 1, "running": 2, "done": 3, "stopped": 4}
    result.sort(key=lambda s: (order.get(s["state"], 9), s["title"].lower()))
    _SVC_CACHE.update(t=time.time(), v=result)
    return result


# ───────────────────────────── journal simplifié ─────────────────────────────

NOISE = [
    re.compile(p) for p in (
        r"^systemd-(sysv|fstab|gpt-auto|rc-local)-generator",
        r"Consumed .* CPU time",
        r"^pam_unix\(cron:session\)",
        r"^pam_unix\(sudo:session\)",
        r"lacks a native systemd unit file",
        r"Please update package to include a native",
        r"compatibility logic is deprecated",
        r"Mount point\s+is not a valid path",
        r"^\(.*\) CMD ",
        r"open-conn-track: timeout opening",
        r"^\[RATELIMIT\]",
        r"HTTP Request: (GET|POST) https://api\.telegram\.org",
        r"^Reloading(\.\.\.| finished in)",
        r"^Reload requested from client PID",
        r"^pam_unix\(systemd-user:session\)",
    )
]

# (motif, traduction, niveau forcé ou None)
def _u(x, short, long):
    return short if re.search(r"\.\w+ - ", x) else long


RULES = [
    (r"Started (.+?)\.?$", lambda m: _u(m[1], "Démarré", f"Démarré : {m[1]}"), "info"),
    (r"Starting (.+?)\.{0,3}$", lambda m: _u(m[1], "Démarrage…", f"Démarrage de {m[1]}…"), "info"),
    (r"Failed to start (.+?)\.?$", lambda m: _u(m[1], "N'a pas réussi à démarrer", f"N'a pas réussi à démarrer : {m[1]}"), "error"),
    (r"Stopped (.+?)\.?$", lambda m: _u(m[1], "Arrêté", f"Arrêté : {m[1]}"), "info"),
    (r"Stopping (.+?)\.{0,3}$", lambda m: _u(m[1], "Arrêt…", f"Arrêt de {m[1]}…"), "info"),
    (r"Reloaded (.+?)\.?$", lambda m: f"Rechargé : {m[1]}", "info"),
    (r"Deactivated successfully", lambda m: "S'est terminé proprement", "info"),
    (r"Finished (.+?)\.?$", lambda m: _u(m[1], "Terminé", f"Terminé : {m[1]}"), "info"),
    (r"Main process exited, code=killed, status=\d+/(\w+)", lambda m: f"Le processus a été tué ({m[1]})", "error"),
    (r"Main process exited, code=exited, status=(\d+)/(\w+)", lambda m: f"Le processus a planté (code {m[1]})", "error"),
    (r"Failed with result '([^']+)'", lambda m: {"exit-code": "Échec : le programme s'est arrêté en erreur",
                                                   "oom-kill": "Échec : tué faute de mémoire",
                                                   "timeout": "Échec : trop long à répondre",
                                                   "signal": "Échec : arrêté par un signal",
                                                   "start-limit-hit": "Échec : trop de redémarrages d'affilée"}
     .get(m[1], f"Échec ({m[1]})"), "error"),
    (r"Scheduled restart job, restart counter is at (\d+)", lambda m: f"Redémarrage automatique n°{m[1]}", "warning"),
    (r"Start request repeated too quickly", lambda m: "Abandon : redémarre en boucle", "error"),
    (r"Out of memory: Killed process \d+ \((.+?)\)", lambda m: f"Mémoire pleine : {m[1]} a été tué", "error"),
    (r"A process of this unit has been killed by the OOM killer", lambda m: "Un processus a été tué : plus de mémoire", "error"),
    (r"Accepted (\w+) for (\S+) from (\S+)", lambda m: f"Connexion SSH de {m[2]} depuis {m[3]}", "info"),
    (r"Failed password for (?:invalid user )?(\S+) from (\S+)", lambda m: f"Mot de passe SSH refusé ({m[1]}) depuis {m[2]}", "warning"),
    (r"Invalid user (\S+) from (\S+)", lambda m: f"Utilisateur SSH inconnu « {m[1]} » depuis {m[2]}", "warning"),
    (r"Disconnected from (?:user )?(\S+) (\S+)", lambda m: f"Déconnexion SSH ({m[1]})", "info"),
    (r"(\S+):(\d+): Unknown key '([^']+)'", lambda m: f"Config bizarre dans {os.path.basename(m[1])} (ligne {m[2]}) : « {m[3]} » ignoré", "warning"),
    (r"error handling ([\d.]+|\[[0-9a-f:]+\]):\d+: (?:read tcp .*: )?(.+)$",
     lambda m: f"Connexion de {m[1]} interrompue : {m[2][:80]}", "warning"),
    (r"Under-voltage|under-voltage", lambda m: "Sous-tension détectée", "error"),
    (r"I/O error", lambda m: "Erreur d'entrée/sortie disque", "error"),
    (r"temperature above threshold|Package temperature above", lambda m: "Le processeur chauffe trop", "warning"),
    (r"Network is unreachable", lambda m: "Réseau injoignable", "warning"),
    (r"Connection refused", lambda m: "Connexion refusée", "warning"),
    (r"(?i)traceback \(most recent call last\)", lambda m: "Erreur Python (traceback)", "error"),
]
RULES = [(re.compile(p), f, lvl) for p, f, lvl in RULES]

ERR_WORDS = re.compile(r"(?i)\b(error|erreur|exception|fatal|panic|critical|failed|segfault)\b")
WARN_WORDS = re.compile(r"(?i)\b(warn|warning|attention|deprecated|timeout|timed out|retry)\b")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_NUMS = re.compile(r"\b\d+\b")


def _msg(v):
    if isinstance(v, list):
        try:
            return bytes(v).decode("utf-8", "replace")
        except Exception:
            return str(v)
    return str(v or "")


def read_journal(hours=12, priority=None, unit=None, limit=600):
    cmd = ["journalctl", "-o", "json", "--no-pager", "--since", f"-{int(hours)}h", "-n", str(limit)]
    if priority is not None:
        cmd += ["-p", str(priority)]
    if unit:
        cmd += ["-u", unit]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return []
    entries = []
    for line in out.splitlines():
        try:
            entries.append(json.loads(line))
        except ValueError:
            pass
    return entries


SECRETS = [
    (re.compile(r"bot\d{6,}:[\w-]{20,}"), "bot•••"),
    (re.compile(r"(?i)((?:token|apikey|api_key|key|password|passwd|secret|auth)[=:]\s*)[^\s&,;\"']+"), r"\1•••"),
    (re.compile(r"(?i)(bearer\s+)[\w.\-]+"), r"\1•••"),
]
_PREFIXES = [
    re.compile(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s*(?:-\s*)?"),
    re.compile(r"^\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\s+"),
    re.compile(r"^\[\d{4}-\d{2}-\d{2}[^\]]*\]\s*"),
]
_LOGFMT = re.compile(r'level=(\w+).*?msg="((?:[^"\\]|\\.)*)"')
_INLINE_LEVEL = re.compile(r"^(?:-\s*)?(?:\[)?(DEBUG|INFO|WARN(?:ING)?|ERROR|CRITICAL|FATAL)(?:\])?\s*[-:|]?\s*", re.I)
_UNIT_SUFFIX = re.compile(r"\s*:\s*\S+\.(?:service|timer|socket|mount|path|target|scope) - .*$")


def clean_message(msg):
    """Retire l'horodatage et le niveau recopiés par les applis, masque les secrets.
    Renvoie (texte, niveau détecté ou None)."""
    lvl = None
    m = _LOGFMT.search(msg)
    if m:
        lvl, msg = m[1], m[2].replace('\\"', '"')
    for rx in _PREFIXES:
        msg = rx.sub("", msg, count=1)
    m = _INLINE_LEVEL.match(msg)
    if m:
        lvl = lvl or m[1]
        msg = msg[m.end():]
    m = re.match(r"^(ERR|WRN|INF|DBG)\s+", msg)  # façon zerolog (cloudflared)
    if m:
        lvl = lvl or {"ERR": "error", "WRN": "warning"}.get(m[1], "info")
        msg = msg[m.end():]
    m = re.match(r"^(\w+):\s", msg)  # "info: [rss] ..." façon winston
    if m and m[1].lower() in ("info", "warn", "warning", "error", "debug"):
        lvl = lvl or m[1]
        msg = msg[m.end():]
    for rx, rep in SECRETS:
        msg = rx.sub(rep, msg)
    if lvl:
        lvl = lvl.lower()
        lvl = "error" if lvl in ("error", "critical", "fatal", "err", "crit") else \
              "warning" if lvl.startswith("warn") else "info"
    return re.sub(r"\s{2,}", " ", msg).strip(), lvl


def simplify(e):
    msg = _ANSI.sub("", _msg(e.get("MESSAGE"))).strip()
    if not msg:
        return None
    ident = e.get("SYSLOG_IDENTIFIER") or ""
    full = f"{ident}: {msg}" if ident else msg
    if any(r.search(msg) or r.search(full) for r in NOISE):
        return None
    unit = (e.get("_SYSTEMD_UNIT") or e.get("UNIT") or e.get("USER_UNIT") or "")
    # Les messages de systemd « à propos » d'une unité ont UNIT= : on les rattache à elle.
    if e.get("UNIT"):
        unit = e["UNIT"]
    if unit.startswith("session-") or unit.startswith("user@"):
        unit = ""
    try:
        prio = int(e.get("PRIORITY", 6))
    except ValueError:
        prio = 6
    if prio >= 7:
        return None
    level = "error" if prio <= 3 else "warning" if prio == 4 else "info"
    msg, app_level = clean_message(msg)
    if not msg:
        return None
    if app_level and prio >= 6:
        level = app_level

    text = None
    for rx, fn, lvl in RULES:
        m = rx.search(msg)
        if m:
            text = _UNIT_SUFFIX.sub("", fn(m))
            if lvl == "error" or (lvl == "warning" and level == "info"):
                level = lvl
            break
    if text is None:
        text = msg
        if level == "info" and not app_level and ERR_WORDS.search(msg):
            level = "error"
        elif level == "info" and not app_level and WARN_WORDS.search(msg):
            level = "warning"
        if len(text) > 220:
            text = text[:217] + "…"

    source = unit or (ident + ".service" if ident else "")
    friendly = DESCRIPTIONS.get(source, "")
    title = split_desc(friendly)[0] if friendly else (
        source.removesuffix(".service") or ident or "système")
    if ident == "kernel":
        title = "Noyau"
    elif ident in ("sshd", "sshd-session"):
        title = "SSH"
    elif ident == "systemd" and not unit:
        title = "systemd"

    try:
        ts = int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6
    except ValueError:
        ts = time.time()
    return {"time": int(ts), "unit": source.removesuffix(".service"), "title": title,
            "level": level, "message": text, "raw": msg[:600]}


def logs(hours=12, level="all", unit=None):
    if not DESCRIPTIONS:
        services()
    unit_name = (unit + ".service") if unit and "." not in unit else unit
    # Les alertes sont lues à part, avec une grande limite : le bavardage « info »
    # ne doit jamais pousser une erreur hors de la fenêtre demandée.
    # Les lignes « info » récentes sont lues aussi dans tous les cas : certaines
    # deviennent des erreurs une fois traduites (traceback, « failed »…).
    raw = read_journal(hours=hours, priority=4, unit=unit_name, limit=2000)
    seen = {e.get("__CURSOR") for e in raw}
    raw += [e for e in read_journal(hours=hours, unit=unit_name, limit=700 if not unit else 300)
            if e.get("__CURSOR") not in seen]
    groups = {}
    for e in raw:
        s = simplify(e)
        if not s:
            continue
        if level == "error" and s["level"] != "error":
            continue
        if level == "warning" and s["level"] == "info":
            continue
        key = (s["unit"], s["level"], _NUMS.sub("#", s["message"]))
        g = groups.get(key)
        if g:
            g["count"] += 1
            if s["time"] >= g["time"]:
                g["time"], g["message"], g["raw"] = s["time"], s["message"], s["raw"]
            g["firstTime"] = min(g["firstTime"], s["time"])
        else:
            s["count"] = 1
            s["firstTime"] = s["time"]
            groups[key] = s
    items = sorted(groups.values(), key=lambda x: x["time"], reverse=True)[:200]
    for i, it in enumerate(items):
        it["id"] = f"{it['time']}-{i}-{abs(hash((it['unit'], it['message']))) % 10**8}"
    counts = {"error": 0, "warning": 0, "info": 0}
    for it in items:
        counts[it["level"]] += it["count"]
    return {"hours": hours, "counts": counts, "entries": items}


# ───────────────────────────── HTTP ─────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "mlab-agent/" + VERSION

    def log_message(self, fmt, *args):
        pass  # silencieux : sinon l'agent pollue lui-même le journal

    def _allowed(self):
        try:
            ip = ipaddress.ip_address(self.client_address[0].removeprefix("::ffff:"))
        except ValueError:
            return False
        if not any(ip in n for n in ALLOWED_NETS):
            return False
        auth = self.headers.get("Authorization", "")
        given = auth.removeprefix("Bearer ").strip()
        return hmac.compare_digest(given.encode(), TOKEN.encode())

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self._allowed():
            return self._send(401, {"error": "non autorisé"})
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        try:
            if u.path == "/api/ping":
                return self._send(200, {"ok": True, "hostname": socket.gethostname(), "version": VERSION})
            if u.path == "/api/overview":
                return self._send(200, overview())
            if u.path == "/api/history":
                with SAMPLER.lock:
                    return self._send(200, {"points": list(SAMPLER.history)})
            if u.path == "/api/services":
                return self._send(200, {"services": services()})
            if u.path == "/api/logs":
                hours = max(1, min(int(q.get("hours", "12")), 168))
                level = q.get("level", "all")
                unit = q.get("unit") or None
                if unit and not re.fullmatch(r"[\w@.\-]+", unit):
                    return self._send(400, {"error": "unité invalide"})
                return self._send(200, logs(hours, level, unit))
            return self._send(404, {"error": "introuvable"})
        except Exception as e:
            return self._send(500, {"error": str(e)})

    def do_POST(self):
        if not self._allowed():
            return self._send(401, {"error": "non autorisé"})
        m = re.fullmatch(r"/api/services/([\w@.\-]+)/restart", urlparse(self.path).path)
        if not m:
            return self._send(404, {"error": "introuvable"})
        name = unquote(m[1]).removesuffix(".service")
        known = {s["name"]: s for s in services()}
        if name not in known or not known[name]["canRestart"]:
            return self._send(403, {"error": "ce service ne peut pas être redémarré depuis l'app"})
        r = subprocess.run(["systemctl", "restart", name + ".service"], capture_output=True, text=True, timeout=60)
        _SVC_CACHE["t"] = 0
        if r.returncode != 0:
            return self._send(500, {"error": r.stderr.strip() or "échec du redémarrage"})
        return self._send(200, {"ok": True})


def main():
    global SAMPLER
    SAMPLER = Sampler()
    SAMPLER.tick()
    threading.Thread(target=SAMPLER.run, daemon=True).start()
    srv = ThreadingHTTPServer((BIND, PORT), Handler)
    srv.daemon_threads = True
    print(f"mlab-agent {VERSION} sur {BIND}:{PORT}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
