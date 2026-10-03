# Bloutouss

Application iOS qui affiche en temps réel tous les appareils Bluetooth à proximité.

## Fonctionnalités

**Appareils**
- Scan continu des appareils Bluetooth Low Energy, avec force du signal lissée et distance estimée
- Reconnaissance automatique : AirPods/Beats (avec batterie des écouteurs et du boîtier), AirTag et accessoires Localiser, iPhone/Mac/Apple TV (Continuity), iBeacon, Eddystone (UID, URL, TLM), Google Fast Pair, Microsoft Swift Pair, Tile, Samsung SmartTag, RuuviTag (température, humidité, pression), capteurs cardiaques, claviers…
- Recherche, tri (signal, nom, récents, durée de présence) et filtres (signal minimum, type, favoris, nommés, connectables, actifs)
- Favoris et noms personnalisés, alerte quand un favori réapparaît
- Liste des appareils déjà connectés à l'iPhone
- Export CSV de la session

**Fiche appareil**
- Graphique du signal en direct, RSSI min/moyen/max
- Analyse détaillée des annonces (protocoles, données fabricant et de service)

**Connexion GATT**
- Connexion à l'appareil, découverte des services et caractéristiques
- Lecture, écriture (hex ou texte) et notifications en direct
- Batterie, fabricant, modèle, numéros de série et versions lus automatiquement
- Journal des échanges

**Localiser**
- Mode « Flèche » façon Recherche précise : faites un tour sur vous-même, la flèche indique la direction de l'appareil (gyroscope + force du signal), avec la distance et un fond qui vire au vert à l'approche
- Mode « Jauge » : jauge de proximité, tendance (rapprochement / éloignement)
- Vibrations et son de plus en plus rapides

**Radar**
- Vue radar animée des appareils autour de vous (échelle de distance logarithmique)

**Traqueurs**
- Détection des AirTag séparés de leur propriétaire, Tile et SmartTag, avec alerte si un traqueur reste près de vous plus de 10 minutes

**Réglages**
- Calibrage de la distance, réactivité du signal, nettoyage automatique de la liste, vibrations, écran toujours allumé, statistiques

## Récupérer l'IPA

L'IPA est compilée automatiquement par GitHub Actions (workflow **Build IPA**) à chaque push :

1. Onglet **Actions** du dépôt → dernier run de *Build IPA* → artefact **Bloutouss-ipa**.
2. Chaque push publie aussi l'IPA dans la release GitHub `v<MARKETING_VERSION>` (définie dans `project.yml`) ; un tag `v*` publie une release du même nom.

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
