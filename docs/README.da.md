# SubTitle TransFixer

En Mac-app (Swift + SwiftUI), der **oversætter** `.srt`-undertekster mellem sprog
med Claude og **gennemser** undertekstfiler for tekniske og sproglige fejl.
Den begyndte som scriptet `translate-srt.mjs` (engelsk → svensk) og hed
tidligere *Undertextaren*.

Læs på: [English](../README.md) · [Svenska](README.sv.md) · [Norsk](README.nb.md) ·
**Dansk** · [Suomi](README.fi.md) · [Íslenska](README.is.md)

## Funktioner

- **Original og oversættelse side om side.** Hver replik vises med sit
  nummer, sin tidskode, originaltekst og oversættelse, og oversættelsen kan
  redigeres direkte. Et CPS-mærke (tegn pr. sekund) bliver orange eller rødt, når
  en replik er for lang, og et symbol viser linjer, der er længere end maksimum.
- **Alle sprogpar.** Omkring 30 sprog, som vælges under *Fra* og *Til* over
  underteksterne. Med *Fra: Automatisk* registreres originalens sprog
  med macOS' indbyggede sproggenkendelse (offline og gratis), med hints
  fra filnavnet (`_en`, `.ger`, `.French` …), når teksten er tvetydig.
- **Spørgsmål, når Claude er i tvivl.** Claude oversætter altid med sit bedste
  forslag, men kan spørge om De- eller du-form, den talendes
  køn, ordspil eller tilbagevendende termer. Vælg, hvordan spørgsmål håndteres:
  *Sæt på pause, og spørg med det samme* (batchen oversættes så igen med dit
  svar), *Saml spørgsmål* i sidepanelet eller *Spørg aldrig*. Svarene gælder
  for resten af kørslen og kan gemmes i seriens prompt.
- **Et promptbibliotek pr. serie eller film.** Claude kan oprette en prompt til et
  værk – stilguide, personer, ordliste og noter – eventuelt ved hjælp af websøgning
  og replikker fra den indlæste fil. Prompterne gemmes og findes
  automatisk ud fra filnavnet næste gang, f.eks. finder
  `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` prompten til
  *All Creatures Great and Small*. Hver prompt har et målsprog; en prompt
  til et andet sprog kan bruges alligevel eller tjene som udgangspunkt for en ny.
- **Prompten bliver ved med at lære.** Under oversættelsen noterer Claude nye
  personer, termer og iagttagelser. Når oversættelsen er færdig, spørger appen,
  om prompten skal opdateres, og du sætter flueben ved det, der skal beholdes.
- **Import og eksport af prompter.** Importer eksisterende stilguider (`.md`/`.txt`,
  f.eks. filer, der bruges med `STYLE_FILE` i scriptet) eller `.json`-eksporter.
  Claude kan eventuelt opdele en tekst i stilguide, personer og
  ordliste.
- **Gennemgang.** Kontrollerer enhver `.srt`-fil på ethvert sprog – se nedenfor.
- **Brugerflade på seks sprog:** engelsk, svensk, norsk (bokmål),
  dansk, finsk og islandsk. Appen følger macOS-sproget eller
  valget under *Indstillinger → Appsprog*. Claude skriver sine spørgsmål og
  kommentarer på samme sprog.

## Gennemse en undertekstfil

**Gennemse** i sidepanelet (eller ⌥⌘O) kontrollerer enhver `.srt`-fil. En oversættelse kan
også gennemses direkte med knappen **Gennemse** i oversættelsesoversigten.

**Tekniske kontroller** kører lokalt, med det samme og gratis:

| Kategori | Kontrolleres |
|---|---|
| Tidskoder | tidskoder, der ikke kan fortolkes, slut før start, overlap med den næste replik (kan rettes), forkert rækkefølge, for kort (< 0,7 s) eller for lang (> 7 s) visningstid |
| Nummerering | huller og dubletter (kan omnummereres) |
| Linjelængde / læsehastighed | mere end 2 linjer, linjer, der er for lange, for høj CPS |
| Formatering | tomme replikker, dobbelte mellemrum, mellemrum i starten/slutningen, ubalancerede `<i>`/`<b>`/`<u>`-tags |
| Tegnsætning | en linje, der starter med f.eks. `!`, `&` eller `,`; mellemrum før tegnsætning (undtagen fransk ! ? : ;); manglende mellemrum efter (et kolon inde i ord som `1:a`, `S:t`, `TV:n` accepteres); parenteser og anførselstegn, der ikke passer sammen; lille bogstav efter en afsluttet sætning |
| Konsekvens | blandet `...`/`…`, blandede replikstreger (`-`, `- `, `– `) |
| Stavning | gentagne ord (»det det«) |

**Gennemse sprog** lader Claude kontrollere stavning, grammatik, tegnsætning, ordvalg,
konsekvens (f.eks. navne, der staves forskelligt) og replikker, der er svære at
forstå. **Gennemgangen bruger samme prompt som oversættelsen**: grundstilen,
målsprogets regler og værksprofilen med dens stilguide,
personer, ordliste og gemte beslutninger. Rettelserne følger derfor
seriens regler for tiltaleformer, tone og navne, og afvigelser fra
prompten rapporteres.

### Sammenlign med originalen

- Fra oversættelsesoversigten er originalen allerede forbundet.
- Når du åbner en fil, leder appen efter originalen i samme mappe
  (`Show_sv.srt` → `Show_en.srt`, `Show.en.srt`, `Show.srt` …), eller du kan vælge en
  med **Sammenlign med originalfil…**.
- Replikkerne parres ud fra deres tidskoder, så det virker, selv når originalen
  og oversættelsen deler replikkerne forskelligt op. Originalteksten vises
  over hver replik.

Lokalt finder sammenligningen originalreplikker, der mangler i
oversættelsen (og omvendt), kursiv, der er gået tabt, og årstal, beløb og
klokkeslæt, der er ændret eller forsvundet. Med **Gennemse og sammenlign** kontrollerer Claude også
fejloversættelser, indhold, der er udeladt eller tilføjet, navne, tal,
nægtelser og tiltaleformer. Normal komprimering betragtes ikke som en fejl.

Hver bemærkning viser et forslag med fjernet tekst i rødt og ny tekst i grønt.
Vælg **Ret** eller **Ignorer**, eller **Ret alle** for alle tekniske rettelser eller alle
Claudes forslag. Replikker kan redigeres direkte og nulstilles til
originalen. **Gem** skriver den rettede fil.

## Krav

- macOS 14 (Sonoma) eller nyere
- Fuld Xcode 15 eller nyere (Command Line Tools er ikke nok – SwiftUI's
  makroer, f.eks. `@State`, følger kun med Xcode)
- En API-nøgle fra [console.anthropic.com](https://console.anthropic.com)

## Byg og kør

Byg en rigtig `.app`, der kan lægges i mappen Programmer:

```bash
./build-app.sh
```

```bash
open "build/SubTitle TransFixer.app"
```

Eller åbn pakken i Xcode, og tryk på ⌘R:

```bash
open Package.swift
```

Første gang: Åbn **Indstillinger (⌘,)**, og indsæt API-nøglen. Den gemmes i
macOS-nøgleringen. Appen læser også miljøvariablen `ANTHROPIC_API_KEY`,
hvis den er angivet.

### Skift fra Undertextaren

Ved første start kopieres indstillinger, gemte prompter og API-nøglen fra
*Undertextaren*. Intet slettes, så den gamle app fortsætter med at virke.

## API-nøglen og nøgleringen

Nøglen gemmes i macOS-nøgleringen (emnet *SubTitle TransFixer* i
Nøglering) og læses derfra ved hver start. Nøgleringen udleverer kun
nøglen til den samme app, der gemte den, og »den samme app« afgøres
af kodesignaturen. Derfor signerer `build-app.sh` med et udviklercertifikat,
når der er et tilgængeligt:

1. Åbn Xcode → **Settings → Accounts**, og tilføj dit Apple-id (en gratis konto er nok).
2. Vælg kontoen → **Manage Certificates… → + → Apple Development**.
3. Byg med `./build-app.sh`. Det udskriver `✓ Signed with: Apple Development …`.
4. Indtast API-nøglen en sidste gang. Hvis macOS beder om adgang til nøgleringen, så vælg **Tillad altid**.

Uden et certifikat signeres appen ad hoc, og nøglen skal muligvis
indtastes igen efter hver build. Har du flere certifikater, vælger du et med
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## Sådan bruger du den

1. Åbn eller slip en undertekstfil i vinduet (⌘O).
2. Kontroller *Fra* og *Til*. Appen gætter titel og afsnit ud fra
   filnavnet og leder efter en gemt prompt. Hvis der ikke er nogen, så klik på **Opret med Claude…**.
3. Tryk på **Oversæt** (⌘R). Du kan stoppe og fortsætte senere; kun replikker
   uden oversættelse bliver oversat.
4. Kontroller resultatet med filtrene *Spørgsmål*, *For lang*, *Redigeret* og
   *Mislykkedes*. Højreklik på en replik for at oversætte den igen.
5. Tryk på **Gennemse** for at kontrollere oversættelsen, eller på **Gem** (⌘S). Sprogkoden
   i filnavnet erstattes med målsprogets:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, ellers `.srt` → `.sv.srt`.

## Indstillinger

| Indstilling | Standard | I det oprindelige script |
|---|---|---|
| Appsprog | Samme som macOS | – |
| Model | `claude-opus-5-5` | `MODEL` |
| Oversæt fra / til | Automatisk / svensk | – |
| Replikker pr. anmodning | 20 | `BATCH_SIZE` |
| Kontekst (tidligere replikker) | 4 | `CONTEXT` |
| Maks. tegn/sekund | 17 | `MAX_CPS` |
| Maks. tegn pr. linje | 42 | `MAX_LINE_LEN` |
| Grundstil | sprogneutral standard | `STYLE_FILE` (kan indlæses fra en fil) |

Du kan også vælge *Indsats*, og om der skal bruges en reservemodel, når en
anmodning afvises (reserve på serversiden). Sonnet 5.5 og Haiku 5.5 er
billigere alternativer til Opus 5.5.

Grundstilen bruger pladsholderne `{SOURCE_LANGUAGE}`, `{TARGET_LANGUAGE}`,
`{TARGET_RULES}` (målsprogets egne regler, f.eks. du/ni eller du/Sie),
`{MAX_LINE_LEN}` og `{MAX_CPS}`. En grundstil, som du aldrig har redigeret i en
tidligere version, erstattes automatisk med den nye standard.

## Hvor gemmes prompterne?

`~/Library/Application Support/SubTitle TransFixer/profiles.json` – almindelig JSON,
der kan sikkerhedskopieres eller deles. **Indstillinger → Vis i Finder** åbner mappen.

## Lokalisering

Alle tekster, som brugeren ser, skrives på engelsk i koden og omsluttes af
`L("…")`; den engelske tekst er nøglen. Pladsholdere skrives `{0}`, `{1}` …
Oversættelserne ligger i `Sources/SubTitleTransFixer/Localization/Strings+<code>.swift`
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

`check` rapporterer manglende oversættelser, pladsholdere, der afviger, og dublerede
nøgler (en dubleret nøgle ville få appen til at gå ned ved start).

## Symbol

Symbolet ligger i `Assets/`: `AppIcon.svg` er kilden, `AppIcon.icns`
bruges af `build-app.sh`, og `AppIcon-1024.png` er en forhåndsvisning. Hvis Dock eller
Finder stadig viser det gamle symbol efter en build, så kør `killall Dock; killall Finder`.

## Kodens opbygning

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
