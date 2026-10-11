# StemMac

Application macOS native de séparation et de mixage audio, développée par **Big Mistake Studio** en SwiftUI et utilisant le moteur Python de [StemDeck](https://github.com/stemdeckapp/stemdeck).

[Présentation et téléchargement](https://bigmistake.studio/stemmac/) · [Projet original StemDeck](https://github.com/stemdeckapp/stemdeck) · [Licence Apache 2.0](LICENSE)

## Fonctionnalités

- Import de fichiers audio (MP3, WAV, FLAC, M4A) et d’URL YouTube.
- Séparation en voix, batterie, basse, guitare, piano et autres instruments, selon le modèle choisi.
- Studio avec formes d’onde, réglages de volume, mute, solo et lecture en boucle.
- Export de pistes séparées ou du mixage en WAV ou MP3.
- Bibliothèque des traitements, conversion audio et gestion des composants du moteur.

## Installer

Téléchargez le [DMG StemMac](https://bigmistake.studio/stemmac/StemMac.dmg) puis copiez l’application dans Applications.

**macOS 13 ou ultérieur.** Le DMG proposé sur le site est universel (Apple Silicon et Intel).

Au premier lancement, l’assistant télécharge les composants nécessaires : uv, Python 3.12, FFmpeg/ffprobe, une version publiée du backend StemDeck, ses dépendances et les modèles IA. Une connexion Internet et de l’espace disque sont donc nécessaires. Le traitement des fichiers audio est ensuite effectué localement.

Les composants sont installés dans `~/Library/Application Support/StemDeck/` et la bibliothèque est stockée dans `~/Documents/StemDeck/jobs/`. Homebrew n’est pas requis pour l’installation normale. Certains outils et modèles optionnels peuvent nécessiter des outils de compilation.

## Compiler depuis les sources

Prérequis : macOS 13+, Xcode 15.4 ou ultérieur avec le SDK macOS.

```bash
git clone https://github.com/BigMistakeStudio/StemMac.git
cd StemMac
open StemDeck.xcodeproj
```

Dans Xcode, sélectionnez le schéma **StemDeck** et la destination **My Mac**, puis lancez `Cmd+R`. Les noms internes du projet et du schéma sont conservés ; le produit compilé est **StemMac.app**.

Compilation locale sans signature :

```bash
xcodebuild -project StemDeck.xcodeproj -scheme StemDeck \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

L’application se trouve dans `build/DerivedData/Build/Products/Release/StemMac.app`. La signature et la notarisation d’une distribution restent à configurer avec votre compte développeur Apple.

## Architecture

- `StemDeck/Views/` : configuration, import, traitement, studio, bibliothèque et conversion.
- `StemDeck/Services/PythonRuntimeService.swift` : installation et maintenance du backend et de ses outils.
- `BackendService.swift` et `SSEClient.swift` : communication locale avec le backend et suivi des tâches.
- `AudioPlayerService.swift`, `ExportService.swift`, `MixExportService.swift` : lecture et export audio.
- `.github/workflows/build.yml` : compilation macOS sans signature à chaque push et pull request.

Le backend StemDeck est téléchargé depuis ses versions publiées ; il n’est pas recopié dans ce dépôt. Son code source est disponible dans le [dépôt original](https://github.com/stemdeckapp/stemdeck).

La mise à jour des composants Python est distincte de celle de l’application macOS. La clé `StemDeckAppUpdateRepo` est actuellement vide : les mises à jour automatiques du wrapper macOS restent désactivées tant qu’un circuit de releases StemMac n’est pas configuré.

## Licence et crédits

StemMac est distribué sous **Apache License 2.0** : voir [LICENSE](LICENSE) et [NOTICE](NOTICE).

Merci aux auteurs et contributeurs de [stemdeckapp/stemdeck](https://github.com/stemdeckapp/stemdeck), le projet original qui fournit le moteur de séparation audio, également sous [Apache 2.0](https://github.com/stemdeckapp/stemdeck/blob/main/LICENSE).

Les composants externes et les modèles téléchargés à l’exécution conservent leurs propres licences.
