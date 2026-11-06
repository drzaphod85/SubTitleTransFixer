# SubTitle TransFixer

En Mac-app (Swift + SwiftUI) som **översätter** `.srt`-undertexter mellan språk
med Claude och **granskar** undertextfiler efter tekniska och språkliga fel.
Den började som skriptet `translate-srt.mjs` (engelska → svenska) och hette
tidigare *Undertextaren*.

Läs på: [English](../README.md) · **Svenska** · [Norsk](README.nb.md) ·
[Dansk](README.da.md) · [Suomi](README.fi.md) · [Íslenska](README.is.md)

## Funktioner

- **Original och översättning sida vid sida.** Varje replik visas med sitt
  nummer, sin tidkod, originaltext och översättning, och översättningen kan
  redigeras direkt. En CPS-bricka (tecken per sekund) blir orange eller röd när
  en replik är för lång, och en symbol visar rader som är längre än maxlängden.
- **Valfritt språkpar.** Ett trettiotal språk, som väljs under *Från* och *Till*
  ovanför undertexterna. Med *Från: Automatiskt* identifieras originalets språk
  med den inbyggda språkigenkänningen i macOS (offline och gratis), med ledtrådar
  från filnamnet (`_en`, `.ger`, `.French` …) när texten är tvetydig.
- **Frågor när Claude är osäker.** Claude översätter alltid med sitt bästa
  förslag men kan fråga om formellt eller informellt tilltal, talarens kön,
  ordvitsar eller återkommande termer. Välj hur frågor ska hanteras:
  *pausa och fråga direkt* (omgången översätts då igen med ditt svar),
  *samla frågor* i sidopanelen eller *fråga aldrig*. Svaren gäller resten av
  körningen och kan sparas i seriens prompt.
- **Ett promptbibliotek per serie eller film.** Claude kan skapa en prompt för
  ett verk – stilguide, rollfigurer, ordlista och anteckningar – med hjälp av
  webbsökning och repliker från den inlästa filen om du vill. Prompterna sparas
  och hittas automatiskt utifrån filnamnet nästa gång, t.ex. hittar
  `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` prompten för
  *All Creatures Great and Small*. Varje prompt har ett målspråk; en prompt
  för ett annat språk kan användas ändå eller fungera som grund för en ny.
- **Prompten fortsätter att lära sig.** Under översättningen noterar Claude nya
  rollfigurer, termer och iakttagelser. När översättningen är klar frågar appen
  om prompten ska uppdateras, och du bockar för det du vill behålla.
- **Import och export av prompter.** Importera befintliga stilguider (`.md`/`.txt`,
  t.ex. filer som användes med `STYLE_FILE` i skriptet) eller `.json`-exporter.
  Claude kan om du vill dela upp en text i stilguide, rollfigurer och
  ordlista.
- **Granskning.** Kontrollerar valfri `.srt`-fil på valfritt språk – se nedan.
- **Gränssnitt på sex språk:** engelska, svenska, norska (bokmål),
  danska, finska och isländska. Appen följer språket i macOS eller valet
  under *Inställningar → Appspråk*. Claude skriver sina frågor och
  kommentarer på samma språk.

## Granska en undertextfil

**Granska** i sidofältet (eller ⌥⌘O) kontrollerar valfri `.srt`-fil. En
översättning kan också granskas direkt med knappen **Granska** i översättningsvyn.

**Tekniska kontroller** körs lokalt, direkt och kostnadsfritt:

| Kategori | Kontrolleras |
|---|---|
| Tidkoder | tidkoder som inte kan tolkas, slut före start, överlappning med nästa replik (kan åtgärdas), fel ordning, för kort (< 0,7 s) eller för lång (> 7 s) visningstid |
| Numrering | luckor och dubbletter (kan numreras om) |
| Radlängd / läshastighet | fler än 2 rader, för långa rader, för högt CPS |
| Formatering | tomma repliker, dubbla mellanslag, inledande/avslutande mellanslag, obalanserade `<i>`/`<b>`/`<u>`-taggar |
| Interpunktion | en rad som börjar med t.ex. `!`, `&` eller `,`; mellanslag före skiljetecken (utom franska ! ? : ;); mellanslag som saknas efter (kolon inuti ord som `1:a`, `S:t`, `TV:n` godkänns); parenteser och citattecken som inte stämmer; liten bokstav efter en avslutad mening |
| Konsekvens | blandade `...`/`…`, blandade replikstreck (`-`, `- `, `– `) |
| Stavning | upprepade ord (”att att”) |

**Granska språket** låter Claude kontrollera stavning, grammatik, interpunktion,
formuleringar, konsekvens (t.ex. namn som stavas olika) och repliker som är svåra
att förstå. **Granskningen använder samma prompt som översättningen**: grundstilen,
målspråkets regler och verksprofilen med dess stilguide, rollfigurer, ordlista
och sparade beslut. Rättningarna följer därför seriens regler för tilltal, ton
och namn, och avvikelser från prompten rapporteras.

### Jämför med originalet

- Från översättningsvyn är originalet redan kopplat.
- När du öppnar en fil letar appen efter originalet i samma mapp
  (`Show_sv.srt` → `Show_en.srt`, `Show.en.srt`, `Show.srt` …), eller så väljer
  du ett med **Jämför med originalfil…**.
- Replikerna paras ihop utifrån sina tidkoder, så det fungerar även när originalet
  och översättningen delar upp replikerna olika. Originaltexten visas
  ovanför varje replik.

Lokalt hittar jämförelsen repliker i originalet som saknas i översättningen
(och tvärtom), kursiv stil som har försvunnit och årtal, belopp och klockslag
som har ändrats eller försvunnit. Med **Granska och jämför** kontrollerar Claude
också felöversättningar, innehåll som har strukits eller lagts till, namn, tal,
negationer och tilltal. Normal komprimering räknas inte som fel.

### Rätta, ångra och spara

- **Granska språket med Claude** (eller **Granska och jämför med Claude**) är den stora knappen överst i granskningen.
- Varje anmärkning som kan rättas automatiskt har knappen **Åtgärda** och visar ändringen: borttagen text i rött, ny text i grönt, eller den nya tidkoden. Automatiska rättningar finns för överlapp, för kort eller för lång visningstid, sluttid före starttid, för hög CPS (repliken visas längre när det finns plats före nästa), fel ordning (sortera efter tid), numrering, tomma repliker (ta bort), långa rader och fler än två rader (radbryt om), taggar som inte stängs, mellanslag, skiljetecken och konsekvens.
- Anmärkningar utan automatisk rättning har bara **Ignorera** och talar om hur du rättar själv: redigera texten direkt, eller klicka på tiden till vänster om en replik för att ändra tidkoden.
- **Godta alla förslag** använder alla förslag som visas med aktuellt filter – både Claudes och de automatiska rättningarna – i ett enda steg.
- **Ångra** och **Gör om** fungerar för varje rättning, ignorerad anmärkning och redigering. **Återställ allt…** går tillbaka till filen som den var när du öppnade den.
- Ingenting sparas automatiskt. **Spara** (⌘S) skriver tillbaka till filen du öppnade – första gången sparas en kopia av originalet som `<namn>.srt.bak` – och **Spara som…** skriver en ny fil. Appen frågar innan du öppnar en annan fil eller avslutar med osparade ändringar.

### Spela upp videon och rätta tiderna

Om en video med samma namn ligger bredvid undertextfilen – t.ex. `Matador - S01E01.mkv` bredvid `Matador - S01E01.sv.srt` – hittas den automatiskt (eller välj en med **Välj video…**).

- **▶** på varje replik spelar från 5 sekunder före till 5 sekunder efter, med repliken visad i bilden och en ljudkurva under. Klicka i kurvan för att hoppa dit.
- Justera start och slut med ±0,1 s eller **Sätt vid uppspelningsläget**, eller låt **Föreslå från ljudet** hitta var talet börjar och slutar. **Använd tiderna** genomför ändringen (den går att ångra).
- **Kontrollera tidkoderna mot ljudet** analyserar hela avsnittet och föreslår nya tider för repliker som verkar börja eller sluta vid fel tid. Godta dem en och en eller med **Godta alla förslag**.
- Analysen mäter bara ljudstyrka, så musik och ljudeffekter kan lura den – spela upp repliken innan du godtar.
- macOS spelar `.mp4`, `.m4v` och `.mov` på egen hand. `.mkv`, `.avi` och andra format kräver [ffmpeg](https://ffmpeg.org): `brew install ffmpeg`.

## Systemkrav

- macOS 14 (Sonoma) eller senare
- Fullständiga Xcode 15 eller senare (Command Line Tools räcker inte – SwiftUI:s
  makron, som `@State`, följer bara med Xcode)
- En API-nyckel från [console.anthropic.com](https://console.anthropic.com)

## Bygga och köra

Bygg en riktig `.app` som kan läggas i mappen Program:

```bash
./build-app.sh
```

```bash
open "build/SubTitle TransFixer.app"
```

Eller öppna paketet i Xcode och tryck på ⌘R:

```bash
open Package.swift
```

Första gången: öppna **Inställningar (⌘,)** och klistra in API-nyckeln. Den sparas
i nyckelringen i macOS. Appen läser också miljövariabeln `ANTHROPIC_API_KEY`
om den är satt.

### Flytta från Undertextaren

Vid första starten kopieras inställningar, sparade prompter och API-nyckeln från
*Undertextaren*. Ingenting raderas, så den gamla appen fortsätter att fungera.

## API-nyckeln och nyckelringen

Nyckeln sparas i nyckelringen i macOS (objektet *SubTitle TransFixer* i
Nyckelhanteraren) och läses därifrån vid varje start. Nyckelringen lämnar bara
ut nyckeln till samma app som sparade den, och vad som är ”samma app” avgörs
av kodsignaturen. Därför signerar `build-app.sh` med ett utvecklarcertifikat
när det finns ett:

1. Öppna Xcode → **Inställningar → Konton** och lägg till ditt Apple-ID (ett gratiskonto räcker).
2. Markera kontot → **Hantera certifikat… → + → Apple Development**.
3. Bygg med `./build-app.sh`. Det skriver ut `✓ Signed with: Apple Development …`.
4. Ange API-nyckeln en sista gång. Om macOS ber om åtkomst till nyckelringen väljer du **Tillåt alltid**.

Utan certifikat signeras appen ad hoc, och nyckeln kan behöva anges igen efter
varje bygge. Om du har flera certifikat väljer du ett med
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## Ladda ner

Signerade och notariserade versioner finns under
[Releases](https://github.com/drzaphod85/SubTitleTransFixer/releases).
Öppna `.dmg`-filen och dra *SubTitle TransFixer* till Program-mappen.
[CHANGELOG.md](../CHANGELOG.md) beskriver vad som är nytt i varje version.

## Releaser och signering

En release byggs av GitHub Actions (`.github/workflows/release.yml`) när en
versionstagg pushas. Den bygger en universell app (Apple silicon + Intel),
signerar den med *Developer ID*, låter Apple notarisera den och publicerar en
`.dmg` tillsammans med versionens anteckningar från `CHANGELOG.md`.

**En gång: lägg in hemligheterna** (repot på GitHub → **Settings → Secrets and
variables → Actions → New repository secret**):

1. *(Bara om certifikatet inte redan finns i nyckelringen.)* I Xcode → **Inställningar → Konton → Hantera certifikat… → + → Developer ID Application**.
2. I Nyckelhanterare, leta upp *Developer ID Application: …* under **Mina certifikat**,
   högerklicka → **Exportera…**, spara som `.p12` och välj ett lösenord.
3. Kopiera filen som base64: `base64 -i certificate.p12 | pbcopy`
4. Skapa ett appspecifikt lösenord på [account.apple.com](https://account.apple.com)
   → **Inloggning och säkerhet → Appspecifika lösenord**.

| Hemlighet | Värde |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64-texten från steg 3 |
| `MACOS_CERTIFICATE_PASSWORD` | lösenordet från steg 2 |
| `APPLE_ID` | utvecklarkontots Apple-ID (e-post) |
| `APPLE_TEAM_ID` | team-ID (10 tecken, visas på developer.apple.com → Membership) |
| `APPLE_APP_PASSWORD` | det appspecifika lösenordet från steg 4 |

**Varje release:** lägg till ett avsnitt `## [x.y.z]` överst i `CHANGELOG.md`, sedan:

```bash
git tag v1.0.0
```

```bash
git push origin v1.0.0
```

Utan hemligheterna bygger arbetsflödet ändå appen, men osignerad och bara som
utkast till release. Ett bygge kan också startas för hand under **Actions →
Release → Run workflow**; det blir alltid ett utkast.

## Så här använder du appen

1. Öppna eller släpp en undertextfil i fönstret (⌘O).
2. Kontrollera *Från* och *Till*. Appen gissar titel och avsnitt utifrån filnamnet
   och letar efter en sparad prompt. Om det inte finns någon klickar du på **Skapa med Claude…**.
3. Tryck på **Översätt** (⌘R). Du kan stoppa och fortsätta senare; bara repliker
   utan översättning översätts.
4. Kontrollera resultatet med filtren *Frågor*, *För lång*, *Redigerad* och
   *Misslyckad*. Högerklicka på en replik för att översätta den igen.
5. Tryck på **Granska** för att kontrollera översättningen, eller **Spara** (⌘S).
   Språkkoden i filnamnet ersätts med målspråkets:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, annars `.srt` → `.sv.srt`.

## Inställningar

| Inställning | Standard | I det ursprungliga skriptet |
|---|---|---|
| Appspråk | Samma som macOS | – |
| Modell | `claude-opus-5-5` | `MODEL` |
| Översätt från / till | Automatiskt / svenska | – |
| Repliker per förfrågan | 20 | `BATCH_SIZE` |
| Sammanhang (tidigare repliker) | 4 | `CONTEXT` |
| Max tecken/sekund | 17 | `MAX_CPS` |
| Max tecken per rad | 42 | `MAX_LINE_LEN` |
| Grundstil | språkneutral standard | `STYLE_FILE` (kan läsas in från en fil) |

Du kan också välja *Ansträngning* och om en reservmodell ska användas när en
förfrågan avböjs (reserv på serversidan). Sonnet 5.5 och Haiku 5.5 är
billigare alternativ till Opus 5.5.

Grundstilen använder platshållarna `{SOURCE_LANGUAGE}`, `{TARGET_LANGUAGE}`,
`{TARGET_RULES}` (målspråkets egna regler, t.ex. du/ni eller du/Sie),
`{MAX_LINE_LEN}` och `{MAX_CPS}`. En grundstil som du aldrig redigerade i en
tidigare version ersätts automatiskt med den nya standarden.

## Var sparas prompterna?

`~/Library/Application Support/SubTitle TransFixer/profiles.json` – vanlig JSON
som kan säkerhetskopieras eller delas. **Inställningar → Visa i Finder** öppnar mappen.

## Lokalisering

Varje sträng som visas för användaren skrivs på engelska i koden och omsluts av
`L("…")`; den engelska texten är nyckeln. Platshållare skrivs `{0}`, `{1}` …
Översättningarna finns i `Sources/SubTitleTransFixer/Localization/Strings+<code>.swift`
och genereras från JSON:

```bash
python3 scripts/localization.py extract > strings.json
```

```bash
python3 scripts/localization.py generate localization/sv.json
```

```bash
python3 scripts/localization.py check
```

`check` rapporterar översättningar som saknas, platshållare som skiljer sig åt och
dubblerade nycklar (en dubblerad nyckel skulle få appen att krascha vid start).

## Symbol

Symbolen finns i `Assets/`: `AppIcon.svg` är källan, `AppIcon.icns` används
av `build-app.sh` och `AppIcon-1024.png` är en förhandsvisning. Om Dock eller
Finder fortfarande visar den gamla symbolen efter ett bygge kör du `killall Dock; killall Finder`.

## Kodstruktur

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
