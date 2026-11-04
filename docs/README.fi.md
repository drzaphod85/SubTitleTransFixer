# SubTitle TransFixer

Mac-sovellus (Swift + SwiftUI), joka **kääntää** `.srt`-tekstityksiä kielestä
toiseen Clauden avulla ja **tarkistaa** tekstitystiedostoista tekniset ja
kielelliset virheet. Sovellus sai alkunsa skriptistä `translate-srt.mjs`
(englanti → ruotsi), ja sen aiempi nimi oli *Undertextaren*.

Lue: [English](../README.md) · [Svenska](README.sv.md) · [Norsk](README.nb.md) ·
[Dansk](README.da.md) · **Suomi** · [Íslenska](README.is.md)

## Ominaisuudet

- **Alkuperäinen ja käännös rinnakkain.** Jokainen repliikki näytetään
  numeroineen, aikakoodeineen, alkuperäisine teksteineen ja käännöksineen, ja
  käännöstä voi muokata suoraan. CPS-merkki (merkkiä sekunnissa) muuttuu
  oranssiksi tai punaiseksi, kun repliikki on liian pitkä, ja kuvake osoittaa
  enimmäispituutta pidemmät rivit.
- **Mikä tahansa kielipari.** Noin 30 kieltä, jotka valitaan kohdista
  *Lähdekieli* ja *Kohdekieli* repliikkien yläpuolella. Kun valintana on
  *Lähdekieli: Automaattinen*, alkuperäisen kieli tunnistetaan macOS:n
  sisäänrakennetulla kielentunnistuksella (offline ja maksutta), ja jos teksti
  on monitulkintainen, apuna käytetään tiedostonimen vihjeitä (`_en`, `.ger`,
  `.French` …).
- **Kysymyksiä, kun Claude on epävarma.** Claude kääntää aina parhaan
  ehdotuksensa mukaan, mutta voi kysyä teitittelystä tai sinuttelusta, puhujan
  sukupuolesta, sanaleikeistä tai toistuvista termeistä. Valitse, miten
  kysymykset käsitellään: *keskeytä ja kysy heti* (erä käännetään silloin
  uudelleen vastauksesi perusteella), *kerää kysymykset* sivupaneeliin tai
  *älä koskaan kysy*. Vastaukset koskevat ajon loppuosaa, ja ne voi tallentaa
  sarjan kehotteeseen.
- **Kehotekirjasto sarjoittain ja elokuvittain.** Claude voi luoda teokselle
  kehotteen – tyyliopas, hahmot, sanasto ja muistiinpanot – halutessasi
  verkkohaun ja ladatun tiedoston repliikkien avulla. Kehotteet tallennetaan,
  ja ne löytyvät seuraavalla kerralla automaattisesti tiedostonimen perusteella:
  esimerkiksi `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` löytää
  teoksen *All Creatures Great and Small* kehotteen. Jokaisella kehotteella on
  kohdekieli; toisen kielen kehotetta voi silti käyttää tai käyttää pohjana
  uudelle.
- **Kehote oppii jatkuvasti.** Käännöksen aikana Claude kirjaa uusia hahmoja,
  termejä ja havaintoja. Kun käännös on valmis, sovellus kysyy, päivitetäänkö
  kehote, ja voit valita, mitä säilytetään.
- **Kehotteiden tuonti ja vienti.** Tuo olemassa olevia tyylioppaita
  (`.md`/`.txt`, esim. skriptin `STYLE_FILE`-asetuksella käytettyjä tiedostoja)
  tai `.json`-vientitiedostoja. Claude voi halutessasi jakaa tekstin
  tyylioppaaseen, hahmoihin ja sanastoon.
- **Tarkistus.** Tarkistaa minkä tahansa `.srt`-tiedoston millä tahansa
  kielellä – katso alla.
- **Käyttöliittymä kuudella kielellä:** englanti, ruotsi, norja (bokmål),
  tanska, suomi ja islanti. Sovellus noudattaa macOS:n kieltä tai valintaa
  kohdassa *Asetukset → Sovelluksen kieli*. Claude kirjoittaa kysymyksensä ja
  kommenttinsa samalla kielellä.

## Tekstitystiedoston tarkistaminen

**Tarkista** sivupalkissa (tai ⌥⌘O) tarkistaa minkä tahansa `.srt`-tiedoston.
Käännöksen voi tarkistaa myös suoraan käännösnäkymän **Tarkista**-painikkeella.

**Tekniset tarkistukset** tehdään paikallisesti, heti ja maksutta:

| Luokka | Tarkistetaan |
|---|---|
| Aikakoodit | jäsentämättömät aikakoodit, loppu ennen alkua, päällekkäisyys seuraavan repliikin kanssa (voidaan korjata), väärä järjestys, liian lyhyt (< 0,7 s) tai liian pitkä (> 7 s) näyttöaika |
| Numerointi | aukot ja kaksoiskappaleet (voidaan numeroida uudelleen) |
| Rivinpituus / lukunopeus | yli 2 riviä, liian pitkät rivit, liian suuri CPS |
| Muotoilu | tyhjät repliikit, kaksoisvälilyönnit, välilyönnit rivin alussa/lopussa, täsmäämättömät `<i>`/`<b>`/`<u>`-tagit |
| Välimerkit | rivi, joka alkaa esim. merkillä `!`, `&` tai `,`; välilyönti ennen välimerkkiä (paitsi ranskan ! ? : ;); puuttuva välilyönti välimerkin jälkeen (sanojen sisäinen kaksoispiste, kuten `1:a`, `S:t`, `TV:n`, hyväksytään); täsmäämättömät sulkeet ja lainausmerkit; pieni alkukirjain päättyneen lauseen jälkeen |
| Johdonmukaisuus | sekaisin `...`/`…`, sekaisin eri repliikkiviivat (`-`, `- `, `– `) |
| Oikeinkirjoitus | toistuvat sanat (”ja ja”) |

**Tarkista kieli** antaa Clauden tarkistaa oikeinkirjoituksen, kieliopin,
välimerkit, sanamuodot, johdonmukaisuuden (esim. eri tavoin kirjoitetut nimet)
ja vaikeasti ymmärrettävät repliikit. **Tarkistuksessa käytetään samaa
kehotetta kuin käännöksessä**: perustyyliä, kohdekielen sääntöjä ja
teosprofiilia tyylioppaineen, hahmoineen, sanastoineen ja tallennettuine
päätöksineen. Korjaukset noudattavat siis sarjan sääntöjä puhuttelumuodoista,
sävystä ja nimistä, ja poikkeamat kehotteesta raportoidaan.

### Vertaaminen alkuperäiseen

- Käännösnäkymästä tultaessa alkuperäinen on jo yhdistetty.
- Kun avaat tiedoston, sovellus etsii alkuperäistä samasta kansiosta
  (`Show_sv.srt` → `Show_en.srt`, `Show.en.srt`, `Show.srt` …), tai voit valita
  sen kohdasta **Vertaa alkuperäiseen tiedostoon…**.
- Repliikit yhdistetään aikakoodien perusteella, joten vertailu toimii, vaikka
  alkuperäinen ja käännös jakaisivat repliikit eri tavalla. Alkuperäinen teksti
  näytetään jokaisen repliikin yläpuolella.

Paikallisesti vertailu löytää alkuperäisen repliikit, jotka puuttuvat
käännöksestä (ja päinvastoin), kadonneet kursivoinnit sekä vuosiluvut, summat
ja kellonajat, jotka ovat muuttuneet tai kadonneet. **Tarkista ja vertaa**
-toiminnolla Claude tarkistaa lisäksi käännösvirheet, pois jääneen tai lisätyn
sisällön, nimet, luvut, kieltolauseet ja puhuttelumuodot. Tavanomaista
tiivistämistä ei pidetä virheenä.

Jokaisessa huomautuksessa näytetään ehdotus, jossa poistettu teksti on
punaisella ja uusi teksti vihreällä. Valitse **Korjaa** tai **Ohita**, tai
**Korjaa kaikki** kaikille teknisille korjauksille tai kaikille Clauden
ehdotuksille. Repliikkejä voi muokata suoraan ja palauttaa alkuperäisiksi.
**Tallenna** kirjoittaa korjatun tiedoston.

## Vaatimukset

- macOS 14 (Sonoma) tai uudempi
- Täysi Xcode 15 tai uudempi (Command Line Tools ei riitä – SwiftUI:n makrot,
  kuten `@State`, toimitetaan vain Xcoden mukana)
- API-avain osoitteesta [console.anthropic.com](https://console.anthropic.com)

## Kokoaminen ja käynnistäminen

Kokoa oikea `.app`, jonka voi siirtää Ohjelmat-kansioon:

```bash
./build-app.sh
```

```bash
open "build/SubTitle TransFixer.app"
```

Tai avaa paketti Xcodessa ja paina ⌘R:

```bash
open Package.swift
```

Ensimmäisellä kerralla: avaa **Asetukset (⌘,)** ja liitä API-avain. Se
tallennetaan macOS:n avainnippuun. Sovellus lukee myös
`ANTHROPIC_API_KEY`-ympäristömuuttujan, jos se on asetettu.

### Siirtyminen Undertextarenista

Ensimmäisellä käynnistyskerralla asetukset, tallennetut kehotteet ja API-avain
kopioidaan *Undertextarenista*. Mitään ei poisteta, joten vanha sovellus toimii
edelleen.

## API-avain ja avainnippu

Avain tallennetaan macOS:n avainnippuun (kohde *SubTitle TransFixer*
Avainnippujen hallinnassa), ja se luetaan sieltä jokaisella käynnistyskerralla.
Avainnippu luovuttaa avaimen vain samalle sovellukselle, joka sen tallensi, ja
”sama sovellus” määräytyy koodin allekirjoituksen perusteella. Siksi
`build-app.sh` allekirjoittaa sovelluksen kehittäjävarmenteella, jos sellainen
on saatavilla:

1. Avaa Xcode → **Settings → Accounts** ja lisää Apple ID:si (ilmainen tili riittää).
2. Valitse tili → **Manage Certificates… → + → Apple Development**.
3. Kokoa komennolla `./build-app.sh`. Se tulostaa `✓ Signed with: Apple Development …`.
4. Syötä API-avain vielä viimeisen kerran. Jos macOS pyytää pääsyä avainnippuun, valitse **Salli aina**.

Ilman varmennetta sovellus allekirjoitetaan ad hoc -allekirjoituksella, ja
avain on ehkä syötettävä uudelleen jokaisen koonnin jälkeen. Jos varmenteita
on useita, valitse yksi komennolla
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## Käyttö

1. Avaa tekstitystiedosto tai pudota se ikkunaan (⌘O).
2. Tarkista *Lähdekieli* ja *Kohdekieli*. Sovellus päättelee nimen ja jakson
   tiedostonimestä ja etsii tallennettua kehotetta. Jos sellaista ei ole,
   valitse **Luo Clauden avulla…**.
3. Paina **Käännä** (⌘R). Voit pysäyttää ja jatkaa myöhemmin; vain repliikit,
   joilla ei ole käännöstä, käännetään.
4. Tarkista tulos suodattimilla *Kysymykset*, *Liian pitkä*, *Muokattu* ja
   *Epäonnistunut*. Käännä repliikki uudelleen napsauttamalla sitä hiiren
   oikealla painikkeella.
5. Tarkista käännös painamalla **Tarkista**, tai paina **Tallenna** (⌘S).
   Tiedostonimen kielikoodi korvataan kohdekielen koodilla:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, muuten `.srt` → `.sv.srt`.

## Asetukset

| Asetus | Oletus | Alkuperäisessä skriptissä |
|---|---|---|
| Sovelluksen kieli | Sama kuin macOS | – |
| Malli | `claude-opus-5-5` | `MODEL` |
| Lähdekieli / kohdekieli | Automaattinen / ruotsi | – |
| Repliikkejä pyyntöä kohden | 20 | `BATCH_SIZE` |
| Konteksti (aiemmat repliikit) | 4 | `CONTEXT` |
| Enintään merkkiä sekunnissa | 17 | `MAX_CPS` |
| Enintään merkkiä riviä kohden | 42 | `MAX_LINE_LEN` |
| Perustyyli | kielineutraali oletus | `STYLE_FILE` (voidaan ladata tiedostosta) |

Voit myös valita *Panostuksen* ja sen, käytetäänkö varamallia, jos pyyntö
hylätään (palvelinpuolen varamalli). Sonnet 5.5 ja Haiku 5.5 ovat Opus 5.5:tä
edullisempia vaihtoehtoja.

Perustyylissä käytetään paikkamerkkejä `{SOURCE_LANGUAGE}`, `{TARGET_LANGUAGE}`,
`{TARGET_RULES}` (kohdekielen omat säännöt, esim. du/ni tai du/Sie),
`{MAX_LINE_LEN}` ja `{MAX_CPS}`. Jos et ole koskaan muokannut perustyyliä
aiemmassa versiossa, se korvataan automaattisesti uudella oletuksella.

## Missä kehotteet säilytetään?

`~/Library/Application Support/SubTitle TransFixer/profiles.json` – tavallista
JSONia, jonka voi varmuuskopioida tai jakaa. **Asetukset → Näytä Finderissa**
avaa kansion.

## Lokalisointi

Jokainen käyttäjälle näkyvä merkkijono kirjoitetaan koodissa englanniksi ja
kääritään muotoon `L("…")`; englanninkielinen teksti on avain. Paikkamerkit
kirjoitetaan `{0}`, `{1}` … Käännökset ovat tiedostoissa
`Sources/SubTitleTransFixer/Localization/Strings+<code>.swift`, ja ne
luodaan JSONista:

```bash
python3 scripts/localization.py extract > strings.json
```

```bash
python3 scripts/localization.py generate localization/sv.json
```

```bash
python3 scripts/localization.py check
```

`check` raportoi puuttuvat käännökset, toisistaan poikkeavat paikkamerkit ja
kaksoisavaimet (kaksoisavain kaataisi sovelluksen käynnistettäessä).

## Kuvake

Kuvake on kansiossa `Assets/`: `AppIcon.svg` on lähdetiedosto, `AppIcon.icns`
on `build-app.sh`:n käyttämä ja `AppIcon-1024.png` on esikatselukuva. Jos Dock
tai Finder näyttää koonnin jälkeen yhä vanhaa kuvaketta, suorita
`killall Dock; killall Finder`.

## Koodin rakenne

```
Sources/SubTitleTransFixer/
├── SubTitleTransFixerApp.swift   the app, menus, AppModel
├── Core/
│   ├── AppInfo.swift             names, identifiers, migration from Undertextaren
│   ├── SRT.swift                 parser/serializer, timecodes, title from file name
│   ├── Language.swift            language list, target-language rules, detection
│   ├── AnthropicClient.swift     Messages API (raw HTTP), retry/backoff, JSON parsing
│   ├── PromptBuilder.swift       base style + work profile + decisions, for translation and review
│   ├── TranslationSession.swift  translation engine, questions, suggestions
│   ├── PromptLibrary.swift       saved prompts, matching against titles
│   ├── ProfileGenerator.swift    Claude creates, improves or structures a prompt
│   ├── PromptImporter.swift      import/export of prompts (.md/.txt/.json)
│   ├── SubtitleChecker.swift     technical checks of an .srt file
│   ├── ReviewSession.swift       review: issues, fixes, comparison, Claude review
│   ├── ReviewModels.swift        issues, categories, severity
│   ├── TextDiff.swift            word-level diff to show changes
│   ├── AppSettings.swift         settings + keychain
│   └── Models.swift              data types
├── Localization/                 L(), UI languages and translation tables
└── Views/                        SwiftUI views
scripts/localization.py           extract, generate and check translations
```
