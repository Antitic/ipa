# Wave

Détecteur d'ondes pour iPhone : caméras et micros cachés, satellites, réseau, champ magnétique.

## Fonctions

| Onglet | Contenu |
|---|---|
| **Détecteur** | Bluetooth (marque, modèle, traceurs AirTag/Tile/SmartTag, mode chaud/froid), réseau local (caméras IP, ports, Bonjour, pages web), infrarouge (LED de vision nocturne, reflets d'objectif), ultrasons (FFT 0–24 kHz) |
| **Satellites** | GPS, Galileo, GLONASS, BeiDou et ISS au-dessus de toi, calculés depuis les orbites CelesTrak ; prochains passages de l'ISS |
| **Réseau** | Type de connexion, IP locale et publique, opérateur, passerelle, test de latence et de débit |
| **Magnéto** | Champ magnétique en µT, anomalies, détecteur de métaux avec son |

## Compiler l'IPA avec GitHub Actions

1. Crée un dépôt vide sur GitHub (privé si tu veux), par exemple `wave`.
2. Depuis ce dossier :
   ```bash
   git remote add origin git@github.com:TON_PSEUDO/wave.git
   git push -u origin main
   ```
3. L'onglet **Actions** lance « Build IPA » (environ 5 min).
4. L'IPA apparaît dans **Releases** (`Wave build N` → `Wave.ipa`). Ouvre ce lien sur l'iPhone, télécharge, puis installe avec SideStore (ou dans LiveContainer).

Chaque `git push` sur `main` recompile une nouvelle version. Tu peux aussi relancer à la main : Actions → Build IPA → Run workflow.

L'IPA n'est pas signée : c'est SideStore qui la signe avec ton compte à l'installation.

## Compiler sur le Mac (optionnel)

```bash
brew install xcodegen
xcodegen generate
open Wave.xcodeproj
```

## Limites d'iOS

- Pas de scan des réseaux Wi‑Fi alentour ni de leur puissance, pas d'infos sur les antennes mobiles.
- Pas d'accès aux signaux GNSS reçus : les satellites sont **calculés**, pas captés.
- Pas d'adresse MAC des appareils Bluetooth ni du réseau local (sauf quand un appareil l'annonce lui-même via AirPlay).
- Le micro capte jusqu'à environ 20 kHz.

## Structure

```
project.yml                  Projet XcodeGen (Info.plist, permissions)
.github/workflows/build.yml  Compilation + release de l'IPA
Wave/App                     Point d'entrée, thème, générateur de son
Wave/Detector                Bluetooth, réseau local, infrarouge, ultrasons
Wave/Satellites              Orbites CelesTrak, propagation, carte du ciel
Wave/Network                 Fiche réseau et test de débit
Wave/Magnet                  Magnétomètre et détecteur de métaux
```
