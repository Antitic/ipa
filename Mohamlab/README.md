# Mohamlab — la console du Homelab sur iPhone

Une app iOS en skeuomorphisme assumé : plaque de firme en laiton, tubes Nixie, manomètres à aiguille
sous verre bombé, vu-mètres rétroéclairés, oscilloscope à phosphore vert, baie 19 pouces avec étiquettes
Dymo, fiches techniques tapées à la machine et journal qui sort d'une imprimante à aiguilles sur du papier
listing à bandes vertes.

```
mohamlab/
├── agent/                 l'API qui tourne sur le Homelab (Python + psutil)
│   ├── mlab_agent.py
│   └── install.sh
├── MohamLab/              l'app SwiftUI (iOS 17+)
│   ├── App/               point d'entrée + console d'onglets
│   ├── Model/             modèles JSON, client HTTP, store, données de démo
│   ├── Design/            matières (alu brossé, noyer, papier), voyants, jauges, commandes
│   ├── Views/             Tableau · Services · Fiche · Journal · Réglages
│   └── Resources/         icône, couleur de lancement
├── project.yml            projet Xcode (XcodeGen)
├── build_ipa.sh           fabrique MohamLab.ipa sur un Mac
└── .github/workflows/     fabrique l'IPA + des captures d'écran sur GitHub
```

## 1. L'agent sur le serveur (déjà installé)

`mlab-agent` tourne sur le Homelab comme service systemd, port **8787**. Il n'accepte que Tailscale
(100.64.0.0/10), le réseau local et localhost, **et** exige un jeton.

```bash
sudo cat /etc/mlab-agent/token          # le jeton à coller dans l'app
systemctl status mlab-agent             # état
sudo ./agent/install.sh                 # réinstaller / mettre à jour
```

| Route | Ce qu'elle renvoie |
|---|---|
| `GET /api/overview` | CPU (global + cœurs), RAM, swap, disques, débits réseau et disque, températures, ventilateur, alimentation, gros consommateurs, compteurs de services et d'alertes |
| `GET /api/history` | une heure d'historique (un point toutes les 15 s) |
| `GET /api/services` | tous tes services maison + les services système utiles : état, mémoire, ports, uptime, redémarrages |
| `GET /api/logs?hours=24&level=all\|warning\|error&unit=kloz` | journal **simplifié** : bruit filtré, messages systemd traduits en français, doublons regroupés (×12), secrets masqués |
| `POST /api/services/<nom>/restart` | redémarre un service (jamais `tailscaled`, `ssh`, `mlab-agent`, `NetworkManager`) |

## 2. Fabriquer l'IPA

Il faut macOS + Xcode 15 ou plus récent (le Mac M1 Max fait très bien l'affaire).

**Sur le Mac :**

```bash
./build_ipa.sh          # installe XcodeGen si besoin, compile, produit MohamLab.ipa (non signée)
```

Puis installe `MohamLab.ipa` sur l'iPhone avec **Sideloadly**, **AltStore** ou **SideStore** (ils la
signent avec ton identifiant Apple ; avec un compte gratuit, à re-signer tous les 7 jours).

Variante directe : `xcodegen generate && open MohamLab.xcodeproj`, choisis ton équipe dans
*Signing & Capabilities*, branche l'iPhone, ▶︎.

**Sans Mac — via GitHub :** pousse ce dossier dans un dépôt GitHub. Le workflow `IPA` compile sur un
Mac de GitHub et publie deux artefacts : `MohamLab-ipa` (l'IPA) et `MohamLab-captures` (une capture
du simulateur pour chaque écran, en mode démo).

## 3. Brancher l'app

1. Tailscale actif sur l'iPhone.
2. Onglet **Réglages** → adresse `http://100.100.226.91:8787`, colle le jeton, **Tester** puis **Appliquer**.
3. Tant qu'aucun jeton n'est saisi, l'app tourne en **mode démo** (données fictives qui bougent).

## Les écrans

- **Tableau** — plaque de firme (voyant de liaison, compteur de disponibilité à tambours), tubes Nixie
  (services en marche, en panne, alertes 24 h), quatre manomètres (processeur, mémoire, disque,
  température) qui font un balayage d'auto-test au lancement, vu-mètres réception/émission, oscilloscope
  sur une heure avec bouton rotatif de voie, bargraphes par cœur + charge moyenne sur LCD, gros
  consommateurs, plaque signalétique.
- **Services** — une vraie baie : un module 1U par service avec LED d'état (clignote rouge en cas de
  panne), mémoire en bargraphe, ports en étiquettes Dymo, rangés par famille. Touches de présélection
  pour filtrer.
- **Fiche** — fiche technique tapée à la machine sur un porte-bloc, tampon d'état, derniers événements
  du service en ruban rouge/noir, et le bouton **Redémarrer** sous capot de sécurité (soulever, puis
  appuyer sur le champignon).
- **Journal** — imprimante avec deux boutons rotatifs (niveau, période) et compteurs 7 segments ; les
  événements sortent sur papier listing, tampons « ERREUR » / « ALERTE ». Toucher une ligne montre le
  message brut.
- **Réglages** — adresse et jeton dans des fentes à phosphore, interrupteur à levier pour le mode démo,
  bouton rotatif pour la cadence de relève (2 à 30 s).

Tirer vers le bas sur n'importe quel écran force une relève. Le jeton est rangé dans le trousseau iOS.

## Pour développer

Arguments de lancement utiles (schéma Xcode → *Run* → *Arguments*) :
`-forceDemo YES`, `-startTab 0…3`, `-dashScroll 0…7`, `-openService kloz`.
