# Pin

L'iPod de l'écosystème dipherant, en SwiftUI : un écran en haut, une molette cliquable en bas.

| Section | Ce qu'elle fait | Passe par le serveur ? |
| --- | --- | --- |
| Musique | Lit les morceaux épinglés sur ton profil Telegram, en arrière-plan et sur l'écran verrouillé | Oui (`/api/musique`) |
| WhatsApp | Discussions, texte, images, vocaux, dictée d'Apple | Oui (`/api/whatsapp`) |
| Photos | Appareil photo (enregistre dans la Pellicule), Pellicule, envoi sur WhatsApp | Non |
| Claude | claude.ai dans l'écran, avec tes discussions | Non (direct) |

Le serveur est Pin, sur le homelab (`~/.pin`, port 8210, `pin.dipherant.xyz`).

## La molette

- **Tourner** : défiler (un cran = un retour haptique).
- **Centre** : valider. Dans une conversation : envoyer le texte, ou ouvrir l'image / lire le vocal sélectionné.
- **Centre maintenu** (conversation) : enregistrer un vocal, relâcher pour l'envoyer.
- **MENU** : retour. **MENU maintenu** : menu principal.
- **⏮ ⏭** : morceau précédent / suivant. Dans une conversation : ⏮ dictée, ⏭ joindre une photo. Appareil photo : changer de caméra.
- **⏯** : lecture / pause.
- En lecture : la molette règle le volume ; centre = mode avance rapide.

## Récupérer l'IPA

Workflow **Build Pin IPA** : artefact `Pin-ipa`, et release `pin-v<version>`. IPA non signée, à installer avec SideStore, AltStore ou Sideloadly.

## Côté serveur

- `TG_API_ID` et `TG_API_HASH` (my.telegram.org › API development tools) dans `~/.pin/pin.env` pour la musique.
- ffmpeg convertit les vocaux (OGG/Opus ↔ M4A).

## Compiler soi-même (macOS)

```sh
cd Pin
swift outils/icone.swift Pin/Ressources/Assets.xcassets/AppIcon.appiconset/icon.png
brew install xcodegen && xcodegen generate
open Pin.xcodeproj
```

iOS 17 minimum, iPhone, portrait.
