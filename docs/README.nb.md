# SubTitle TransFixer

En Mac-app (Swift + SwiftUI) som **oversetter** `.srt`-undertekster mellom språk
med Claude og **gjennomgår** undertekstfiler for tekniske og språklige feil.
Den begynte som skriptet `translate-srt.mjs` (engelsk → svensk) og het
tidligere *Undertextaren*.

Les på: [English](../README.md) · [Svenska](README.sv.md) · **Norsk** ·
[Dansk](README.da.md) · [Suomi](README.fi.md) · [Íslenska](README.is.md)

## Funksjoner

- **Original og oversettelse side om side.** Hver replikk vises med
  nummer, tidskode, originaltekst og oversettelse, og oversettelsen kan
  redigeres direkte. Et CPS-merke (tegn per sekund) blir oransje eller rødt når
  en replikk er for lang, og et symbol viser linjer som er lengre enn maksimum.
- **Alle språkpar.** Omtrent 30 språk, valgt under *Fra* og *Til* over
  replikkene. Med *Fra: Automatisk* gjenkjennes språket i originalen
  med den innebygde språkgjenkjenningen i macOS (frakoblet og gratis), med hint
  fra filnavnet (`_en`, `.ger`, `.French` …) når teksten er tvetydig.
- **Spørsmål når Claude er usikker.** Claude oversetter alltid med sitt beste
  forslag, men kan spørre om formell eller uformell tiltale, kjønnet til den som
  snakker, ordspill eller tilbakevendende termer. Velg hvordan spørsmål håndteres:
  *Sett på pause og spør med en gang* (bolken oversettes da på nytt med svaret
  ditt), *Samle spørsmål* i sidepanelet eller *Spør aldri*. Svarene gjelder
  for resten av kjøringen og kan arkiveres i seriens prompt.
- **Et promptbibliotek per serie eller film.** Claude kan lage en prompt for et
  verk – stilguide, personer, ordliste og notater – eventuelt ved hjelp av nettsøk
  og replikker fra den innlastede filen. Prompter arkiveres og blir funnet
  automatisk fra filnavnet neste gang, f.eks. finner
  `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` prompten for
  *All Creatures Great and Small*. Hver prompt har et målspråk; en prompt
  for et annet språk kan brukes likevel eller tjene som utgangspunkt for en ny.
- **Prompten lærer hele tiden.** Under oversettelsen noterer Claude nye
  personer, termer og observasjoner. Når oversettelsen er ferdig, spør appen
  om prompten skal oppdateres, og du huker av for det du vil beholde.
- **Import og eksport av prompter.** Importer eksisterende stilguider (`.md`/`.txt`,
  f.eks. filer som brukes med `STYLE_FILE` i skriptet) eller `.json`-eksporter.
  Claude kan eventuelt dele opp en tekst i stilguide, personer og
  ordliste.
- **Gjennomgang.** Kontrollerer alle `.srt`-filer på alle språk – se nedenfor.
- **Grensesnitt på seks språk:** engelsk, svensk, norsk (bokmål),
  dansk, finsk og islandsk. Appen følger språket i macOS eller
  valget under *Innstillinger → Appspråk*. Claude skriver spørsmålene og
  kommentarene sine på samme språk.

## Gjennomgå en undertekstfil

**Gjennomgå** i sidepanelet (eller ⌥⌘O) kontrollerer alle `.srt`-filer. En oversettelse kan
også gjennomgås direkte med **Gjennomgå**-knappen i oversettelsesvisningen.

**Tekniske kontroller** kjøres lokalt, umiddelbart og gratis:

| Kategori | Kontrolleres |
|---|---|
| Tidskoder | tidskoder som ikke kan tolkes, slutt før start, overlapping med neste replikk (kan rettes), feil rekkefølge, for kort (< 0,7 s) eller for lang (> 7 s) visningstid |
| Nummerering | hull og duplikater (kan nummereres på nytt) |
| Linjelengde / lesehastighet | mer enn 2 linjer, linjer som er for lange, for høy CPS |
| Formatering | tomme replikker, doble mellomrom, mellomrom først/sist, ubalanserte `<i>`/`<b>`/`<u>`-tagger |
| Tegnsetting | en linje som starter med f.eks. `!`, `&` eller `,`; mellomrom før skilletegn (unntatt fransk ! ? : ;); manglende mellomrom etter (kolon inne i ord som `1:a`, `S:t`, `TV:n` godtas); parenteser og anførselstegn som ikke stemmer overens; liten bokstav etter en avsluttet setning |
| Konsekvens | blandet `...`/`…`, blandede replikkstreker (`-`, `- `, `– `) |
| Staving | gjentatte ord («og og») |

**Gjennomgå språket** lar Claude kontrollere staving, grammatikk, tegnsetting, formuleringer,
konsekvens (f.eks. navn som staves forskjellig) og replikker som er vanskelige å
forstå. **Gjennomgangen bruker samme prompt som oversettelsen**: grunnstilen,
målspråkets regler og verksprofilen med stilguide,
personer, ordliste og arkiverte beslutninger. Rettingene følger derfor
seriens regler for tiltaleformer, tone og navn, og avvik fra
prompten rapporteres.

### Sammenlign med originalen

- Fra oversettelsesvisningen er originalen allerede koblet.
- Når du åpner en fil, ser appen etter originalen i samme mappe
  (`Show_sv.srt` → `Show_en.srt`, `Show.en.srt`, `Show.srt` …), eller du kan velge en
  med **Sammenlign med originalfil…**.
- Replikkene pares etter tidskodene, så det fungerer selv når originalen
  og oversettelsen deler opp replikkene forskjellig. Originalteksten vises
  over hver replikk.

Lokalt finner sammenligningen replikker i originalen som mangler i
oversettelsen (og omvendt), kursiv som har forsvunnet, og årstall, beløp og
klokkeslett som er endret eller borte. Med **Gjennomgå og sammenlign** kontrollerer Claude også
feiloversettelser, innhold som er utelatt eller lagt til, navn, tall,
nektelser og tiltaleformer. Vanlig komprimering regnes ikke som en feil.

### Rette, angre og arkivere

- **Gjennomgå språket med Claude** (eller **Gjennomgå og sammenlign med Claude**) er den store knappen øverst i gjennomgangen.
- Hver merknad som kan rettes automatisk, har knappen **Rett** og viser endringen: fjernet tekst i rødt, ny tekst i grønt, eller den nye tidskoden. Automatiske rettinger finnes for overlapp, for kort eller for lang visningstid, sluttid før starttid, for høy CPS (replikken vises lenger når det er plass før den neste), feil rekkefølge (sorter etter tid), nummerering, tomme replikker (fjern), lange linjer og mer enn to linjer (bryt om), tagger som ikke lukkes, mellomrom, tegnsetting og konsekvens.
- Merknader uten automatisk retting har bare **Ignorer** og forteller hvordan du retter selv: rediger teksten direkte, eller klikk på tiden til venstre for en replikk for å endre tidskoden.
- **Godta alle forslag** bruker alle forslag som vises med gjeldende filter – både Claudes og de automatiske rettingene – i ett trinn.
- **Angre** og **Gjør om** virker for hver retting, ignorert merknad og redigering. **Tilbakestill alt…** går tilbake til filen slik den var da du åpnet den.
- Ingenting arkiveres automatisk. **Arkiver** (⌘S) skriver tilbake til filen du åpnet – første gang lagres en kopi av originalen som `<navn>.srt.bak` – og **Arkiver som…** skriver en ny fil. Appen spør før du åpner en annen fil eller avslutter med endringer som ikke er arkivert.

### Spill av videoen og rett tidene

Hvis en video med samme navn ligger ved siden av undertekstfilen – f.eks. `Matador - S01E01.mkv` ved siden av `Matador - S01E01.sv.srt` – blir den funnet automatisk (eller velg en med **Velg video…**).

- **▶** på hver replikk spiller av fra 5 sekunder før til 5 sekunder etter, med replikken vist i bildet og en lydkurve under. Klikk i kurven for å hoppe dit.
- Juster start og slutt med ±0,1 s eller **Sett ved avspillingsposisjonen**, eller la **Foreslå fra lyden** finne hvor talen begynner og slutter. **Bruk tidene** gjennomfører endringen (den kan angres).
- **Kontroller tidskodene mot lyden** analyserer hele episoden og foreslår nye tider for replikker som ser ut til å begynne eller slutte på feil tidspunkt. Godta dem én og én eller med **Godta alle forslag**.
- Analysen måler bare lydstyrke, så musikk og lydeffekter kan lure den – spill av replikken før du godtar.
- macOS spiller av `.mp4`, `.m4v` og `.mov` på egen hånd. `.mkv`, `.avi` og andre formater krever [ffmpeg](https://ffmpeg.org): `brew install ffmpeg`.

## Krav

- macOS 14 (Sonoma) eller nyere
- Fullstendig Xcode 15 eller nyere (Command Line Tools er ikke nok – SwiftUI-makroer
  som `@State` følger bare med Xcode)
- En API-nøkkel fra [console.anthropic.com](https://console.anthropic.com)

## Bygg og kjør

Bygg en ekte `.app` som kan legges i Programmer-mappen:

```bash
./build-app.sh
```

```bash
open "build/SubTitle TransFixer.app"
```

Eller åpne pakken i Xcode og trykk på ⌘R:

```bash
open Package.swift
```

Første gang: Åpne **Innstillinger (⌘,)** og lim inn API-nøkkelen. Den lagres i
nøkkelringen i macOS. Appen leser også miljøvariabelen `ANTHROPIC_API_KEY`
hvis den er satt.

### Overgang fra Undertextaren

Ved første oppstart kopieres innstillinger, arkiverte prompter og API-nøkkelen fra
*Undertextaren*. Ingenting slettes, så den gamle appen fortsetter å fungere.

## API-nøkkelen og nøkkelringen

Nøkkelen lagres i nøkkelringen i macOS (objektet *SubTitle TransFixer* i
Nøkkelring) og leses derfra ved hver oppstart. Nøkkelringen gir bare
nøkkelen til den samme appen som arkiverte den, og «den samme appen» avgjøres
av kodesignaturen. Derfor signerer `build-app.sh` med et
utviklersertifikat når det finnes et:

1. Åpne Xcode → **Settings → Accounts** og legg til Apple-ID-en din (en gratis konto er nok).
2. Velg kontoen → **Manage Certificates… → + → Apple Development**.
3. Bygg med `./build-app.sh`. Det skrives ut `✓ Signed with: Apple Development …`.
4. Skriv inn API-nøkkelen en siste gang. Hvis macOS ber om tilgang til nøkkelringen, velger du **Tillat alltid**.

Uten sertifikat signeres appen ad hoc, og nøkkelen må kanskje skrives inn
på nytt etter hvert bygg. Har du flere sertifikater, velger du ett med
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## Slik bruker du appen

1. Åpne eller slipp en undertekstfil i vinduet (⌘O).
2. Kontroller *Fra* og *Til*. Appen gjetter tittel og episode ut fra
   filnavnet og ser etter en arkivert prompt. Finnes det ingen, klikker du på **Lag med Claude…**.
3. Trykk på **Oversett** (⌘R). Du kan stoppe og fortsette senere; bare replikker
   uten oversettelse blir oversatt.
4. Kontroller resultatet med filtrene *Spørsmål*, *For lang*, *Redigert* og
   *Mislyktes*. Høyreklikk på en replikk for å oversette den på nytt.
5. Trykk på **Gjennomgå** for å kontrollere oversettelsen, eller **Arkiver** (⌘S). Språkkoden
   i filnavnet erstattes med målspråkets:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, ellers `.srt` → `.sv.srt`.

## Innstillinger

| Innstilling | Standard | I det opprinnelige skriptet |
|---|---|---|
| Appspråk | Samme som macOS | – |
| Modell | `claude-opus-5-5` | `MODEL` |
| Oversett fra / til | Automatisk / svensk | – |
| Replikker per forespørsel | 20 | `BATCH_SIZE` |
| Kontekst (tidligere replikker) | 4 | `CONTEXT` |
| Maks. tegn/sekund | 17 | `MAX_CPS` |
| Maks. tegn per linje | 42 | `MAX_LINE_LEN` |
| Grunnstil | språknøytral standard | `STYLE_FILE` (kan lastes inn fra en fil) |

Du kan også velge *Innsats* og om en reservemodell skal brukes når en
forespørsel blir avvist (reserve på serversiden). Sonnet 5.5 og Haiku 5.5 er
billigere alternativer til Opus 5.5.

Grunnstilen bruker plassholderne `{SOURCE_LANGUAGE}`, `{TARGET_LANGUAGE}`,
`{TARGET_RULES}` (målspråkets egne regler, f.eks. du/ni eller du/Sie),
`{MAX_LINE_LEN}` og `{MAX_CPS}`. En grunnstil som du aldri redigerte i en
tidligere versjon, erstattes automatisk med den nye standarden.

## Hvor lagres promptene?

`~/Library/Application Support/SubTitle TransFixer/profiles.json` – vanlig JSON
som kan sikkerhetskopieres eller deles. **Innstillinger → Vis i Finder** åpner mappen.

## Lokalisering

Alle strenger som brukeren ser, skrives på engelsk i koden og pakkes inn i
`L("…")`; den engelske teksten er nøkkelen. Plassholdere skrives `{0}`, `{1}` …
Oversettelsene ligger i `Sources/SubTitleTransFixer/Localization/Strings+<code>.swift`
og genereres fra JSON:

```bash
python3 scripts/localization.py extract > strings.json
```

```bash
python3 scripts/localization.py generate localization/sv.json
```

```bash
python3 scripts/localization.py check
```

`check` rapporterer manglende oversettelser, plassholdere som er forskjellige, og dupliserte
nøkler (en duplisert nøkkel ville få appen til å krasje ved oppstart).

## Symbol

Symbolet ligger i `Assets/`: `AppIcon.svg` er kilden, `AppIcon.icns`
brukes av `build-app.sh`, og `AppIcon-1024.png` er en forhåndsvisning. Hvis Dock eller
Finder fortsatt viser det gamle symbolet etter et bygg, kjører du `killall Dock; killall Finder`.

## Kodestruktur

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
│   ├── Media.swift               video next to the file, ffmpeg, audio analysis, playback
│   ├── AppSettings.swift         settings + keychain
│   └── Models.swift              data types
├── Localization/                 L(), UI languages and translation tables
└── Views/                        SwiftUI views
scripts/localization.py           extract, generate and check translations
```
