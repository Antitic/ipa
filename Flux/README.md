# Flux

YouTube sans Shorts, sans pubs, sans Google. App iOS native (SwiftUI) qui passe par une instance **Piped** : le téléphone ne contacte jamais un serveur Google — pages, miniatures et vidéos transitent par le proxy de l'instance.

## Ce qu'il y a dedans

- **Accueil** : fil de tes abonnements (ou tendances si tu n'en as pas)
- **Recherche** avec suggestions et pagination
- **Chaînes** avec bouton S'abonner (stocké en local, pas de compte)
- **Lecteur** natif AVKit : plein écran, Picture in Picture, lecture en arrière-plan
- **Import** d'abonnements : Google Takeout (`subscriptions.csv`) ou NewPipe/Piped (`.json`)
- **Shorts masqués partout** (flag Piped, URL `/shorts/`, durée ≤ 60 s, `#shorts`)
- Zéro SDK tiers, zéro cookie, session réseau éphémère

## Obtenir l'IPA

Compilée automatiquement par GitHub Actions (workflow **Build Flux IPA**) à chaque push touchant `Flux/` :

1. Onglet **Actions** → dernier run de *Build Flux IPA* → artefact **Flux-ipa**
2. Ou la release `flux-v<MARKETING_VERSION>` (version définie dans `Flux/project.yml`)

L'IPA n'est pas signée : installe-la avec **SideStore / AltStore**, **Sideloadly** ou **TrollStore**.

## Instance Piped : le point important

Les instances publiques tombent régulièrement (YouTube bloque leurs IP). Si une instance lâche, l'app bascule sur la suivante. Mais le plus fiable — et le plus privé — c'est **ta propre instance** sur ton VPS :

```bash
git clone https://github.com/TeamPiped/Piped-Docker && cd Piped-Docker
./configure-instance.sh   # renseigne frontend / api / proxy (ex: pipedapi.dipherant.xyz)
docker compose up -d
```

Puis dans l'app : Réglages → colle `https://pipedapi.ton-domaine` → *Utiliser cette instance*, et désactive la bascule.

## Développement

```bash
cd Flux
brew install xcodegen
xcodegen generate
open Flux.xcodeproj
```
