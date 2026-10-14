<img src="Resources/AppIcon.png" width="128" alt="Wallastream-icoon: koala met speakers als oren">

# Wallastream

Gratis, open-source menubalk-app voor macOS die de audio van je Mac gesynchroniseerd naar meerdere AirPlay 2-speakers tegelijk stuurt, bijvoorbeeld een HomePod mini en een set AirPlay-speakers. Je kunt alle geluid sturen of alleen gekozen apps. Meldingen en de rest blijven dan gewoon op je Mac spelen.

## Installeren

1. Download `Wallastream-x.y.zip` bij [Releases](../../releases) en sleep `Wallastream.app` naar **Programma's**.
2. De app is niet door Apple genotariseerd. De eerste keer krijg je daarom de melding dat hij niet geopend kan worden. Ga naar **Systeeminstellingen → Privacy en beveiliging** en klik op **Toch openen**.
3. Sta toe dat Wallastream audio opneemt wanneer macOS daarom vraagt.

**Vereisten:** Apple Silicon en de macOS-versie die in `LSMinimumSystemVersion` van de release staat. Die versie hangt af van de Homebrew-libraries waarmee is gebouwd.

## Gebruik

Klik op het luidspreker-icoon in de menubalk. Kies je speakers en een bron (**Alle geluid** of **Gekozen apps**) en zet de schakelaar aan.

- Het geluid loopt ongeveer 2 s achter. Dat komt door de AirPlay-buffer en is nodig om de speakers onderling synchroon te houden.
- Een Mac als ontvanger moet bij **Systeeminstellingen → AirDrop en Handoff → AirPlay-ontvanger** op "Iedereen in hetzelfde netwerk" staan. Een wachtwoord of PIN vul je in de app in.
- Een speaker speelt maar van één afzender tegelijk.

## Hoe het werkt

```
Mac-audio ──(Core Audio process tap)──> Wallastream ──(named pipe, 44,1 kHz/16-bit)──> OwnTone ──AirPlay 2──> speakers
```

| Bestand | Rol |
|---|---|
| `SystemAudioCapture.swift` | Process tap (macOS 14.2+) die alle audio opvangt of alleen gekozen processen. Er is geen virtuele driver nodig. |
| `AudioApps.swift` | Somt de apps met audio op. Helper-processen, zoals die van browsers, worden via de "responsible PID" aan hun app gekoppeld. |
| `PipeWriter.swift` | Zet de audio om naar het pipe-formaat van OwnTone en schrijft non-blocking. |
| `OwnTone.swift` | Start de meegeleverde [OwnTone](https://github.com/owntone/owntone-server) en spreekt de JSON API aan op `localhost:3689`. |
| `AppModel.swift`, `WallastreamApp.swift` | Menubalk-UI (SwiftUI). |

OwnTone verzorgt de multiroom-sync voor AirPlay 2. De gegevens (database, log, pipe) staan in `~/Library/Application Support/Wallastream`.

## Zelf bouwen

Je hebt de Xcode Command Line Tools en Homebrew nodig.

```bash
./scripts/build-owntone.sh   # OwnTone + libraries vanaf de broncode naar ./runtime
./build.sh                   # build/Wallastream.app + build/Wallastream-1.0.zip
```

`build.sh` stopt OwnTone en alle libraries in de app met `dylibbundler`, en ondertekent alles ad-hoc. Met `SIGN_ID="Developer ID Application: …"` onderteken je met een eigen certificaat. Een specifieke OwnTone-versie bouw je met `OWNTONE_REF=<tag of commit>`.

## Licentie

De eigen code valt onder MIT (zie `LICENSE`). De meegeleverde OwnTone valt onder GPL-2.0. De broncode daarvan staat op https://github.com/owntone/owntone-server.
