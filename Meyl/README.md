# Meyl — le courrier de dipherant.xyz sur iPhone

Deux thèmes, au choix dans **Réglages** :

- **Codex** (par défaut) : fond blanc, tout en Garamond (EB Garamond, dans l'esprit des titres
  « Think Different »), illustrations et indicateurs en tramage pixel (Bayer 8×8, animé pendant les
  chargements), dates, compteurs et étiquettes en police bitmap (Silkscreen), accent turquoise.
- **Écritoire** : le thème skeuomorphique d'origine (noyer, cuir surpiqué, casiers en laiton,
  enveloppes crème, sceau de cire).

Les polices sont sous licence SIL Open Font License (fichiers `Resources/Fonts/OFL-*.txt`).

Elle lit le courrier reçu par le serveur mail du homelab (maddy) en passant par le webmail
`mail.dipherant.xyz`, donc par le tunnel Cloudflare : rien à ouvrir sur la box.

```
Meyl/
├── Meyl/
│   ├── App/        point d'entrée, navigation, geste de retour
│   ├── Model/      modèles, client HTTP (/app/v1), store, données de démo
│   ├── Design/     matières (noyer, cuir, papier, laiton, cire) et composants
│   ├── Views/      Connexion · Casiers · Liste · Lettre · Rédaction
│   └── Resources/  icône, couleur de lancement
├── server/app-api.js   copie de l'API ajoutée au webmail
└── project.yml         projet Xcode (XcodeGen)
```

## Ce que fait l'app

- Connexion avec l'adresse et le mot de passe du compte mail (gardés dans le trousseau)
- Les quatre casiers : Réception, Envoyés, Archive, Corbeille, avec compteurs
- Liste paginée, recherche dans tout le courrier, tirer pour relever
- Glisser à gauche : corbeille / archiver (depuis la corbeille : remettre / détruire) ; à droite : lu / non lu
- Lecture du HTML nettoyé par le serveur, sans JavaScript, images distantes bloquées par défaut
- Pièces jointes ouvertes en aperçu (Coup d'œil)
- Écrire, répondre, répondre à tous, transférer, joindre des fichiers
- Relève automatique toutes les 30 s tant que l'app est ouverte

## Côté serveur (déjà en place)

`server/app-api.js` est installé dans `/home/antistic/dipherant-mail/` et branché dans `server.js`
juste avant la page 404. Chaque requête porte les identifiants du compte en HTTP Basic ; ils sont
vérifiés contre maddy (IMAP) et gardés 10 min en mémoire sous forme d'empreinte. Même verrou anti
force brute que la page de connexion (5 échecs → 15 min).

| Route | Rôle |
|---|---|
| `GET /app/v1/me` | adresse + dossiers et compteurs |
| `GET /app/v1/list?box=INBOX&before=<uid>` | 60 lettres par page |
| `GET /app/v1/poll?after=<uid>` | compteurs + nouvelles lettres |
| `GET /app/v1/search?q=…` | recherche dans tous les dossiers |
| `GET /app/v1/message/<box>/<uid>` | en-têtes, texte, pièces jointes (marque comme lu) |
| `GET /app/v1/message/<box>/<uid>/body?img=1` | corps HTML nettoyé |
| `GET /app/v1/attachment/<box>/<uid>/<n>` | pièce jointe |
| `POST /app/v1/move` · `POST /app/v1/flag` | ranger / lu-non lu |
| `POST /app/v1/send` (multipart) | envoyer, copie dans Envoyés |

## L'IPA

Le workflow **Build Meyl IPA** compile à chaque push dans `Meyl/` et publie l'IPA non signée dans
la release `meyl-v<version>`. Les captures d'écran (mode démo) arrivent sur la branche `meyl-captures`.

Pour LiveContainer : télécharge `Meyl.ipa` depuis la release, puis dans LiveContainer **+ → Meyl.ipa**.
