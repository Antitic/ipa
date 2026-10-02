# Bloutouss

Application iOS qui affiche en temps réel tous les appareils Bluetooth à proximité.

## Fonctionnalités

- Scan continu des appareils Bluetooth Low Energy (montres, écouteurs, balises, téléphones, objets connectés…)
- Force du signal (RSSI) et estimation de la distance, mises à jour en direct
- Identification du fabricant (Apple, Samsung, Google, Xiaomi…)
- Recherche, tri (signal, nom, plus récents) et filtre des appareils sans nom
- Fiche détaillée : graphique du signal, services annoncés, données fabricant/service brutes
- Les appareils qui n'émettent plus sont grisés ; tirer la liste vers le bas pour la vider

## Récupérer l'IPA

L'IPA est compilée automatiquement par GitHub Actions (workflow **Build IPA**) à chaque push :

1. Onglet **Actions** du dépôt → dernier run de *Build IPA* → artefact **Bloutouss-ipa**.
2. Pour une version publiée, poussez un tag `v*` (ex. `git tag v1.0.0 && git push --tags`) : l'IPA est jointe à la release GitHub.

L'IPA n'est **pas signée**. Installez-la avec un outil de sideload qui la signe avec votre identifiant Apple :
[AltStore](https://altstore.io), [Sideloadly](https://sideloadly.io), ou TrollStore si votre appareil le permet.

## Compiler soi-même (macOS)

```sh
brew install xcodegen
xcodegen generate
open Bloutouss.xcodeproj
```

iOS 16 minimum.

## Limites d'iOS

- iOS n'autorise les apps tierces qu'à voir les appareils **Bluetooth Low Energy** qui émettent des annonces.
  Les appareils en Bluetooth « classique » uniquement (anciens kits mains libres, certaines enceintes) ne sont pas visibles.
- iOS ne donne pas l'adresse MAC : chaque appareil est identifié par un UUID propre à votre iPhone.
- Beaucoup d'appareils (iPhone, AirPods…) changent régulièrement d'adresse pour protéger la vie privée et peuvent apparaître plusieurs fois.
- La distance est une estimation grossière basée sur le RSSI.
