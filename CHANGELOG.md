# Changelog

## 1.2 (14 oktober 2026)

### Nieuw
- Appicoon: een koala met speakers als oren.
- Versienummer onderin het menu.

### Opgelost
- Kraken en ruis op Macs waarvan de audio-uitvoer niet op 48 kHz draait. De audio wordt nu omgezet vanaf de sample rate van het uitvoerapparaat, en altijd in hele blokken naar OwnTone geschreven.
- HomePod loopt vast als twee mensen er tegelijk naar streamen. Wallastream pakt een speaker niet meer automatisch terug als iemand anders hem overneemt (OwnTone-patch `patches/0001-airplay_shared-reconnect.patch`). Er verschijnt een melding met een knop **Opnieuw proberen**.
- De opname start opnieuw als de standaard audio-uitvoer verandert.

## 1.1 (niet gepubliceerd)

Deze versie is alleen intern getest en niet als release gepubliceerd. Alle wijzigingen uit 1.1 zitten in 1.2.

## 1.0 (14 oktober 2026)

Eerste release.
- Mac-audio gesynchroniseerd naar meerdere AirPlay 2-speakers, via de meegeleverde OwnTone.
- Bron: alle geluid of alleen gekozen apps. Meldingen en andere apps blijven op de Mac spelen.
- Volume per speaker.
- Melding en invoer voor een wachtwoord of PIN als een speaker weigert.
