# Undertextaren

En Mac-app (Swift + SwiftUI) som översätter `.srt`-undertexter mellan språk
med Claude. Från början engelska → svenska, nu valfritt språkpar. Den bygger på samma logik och stilguide som
skriptet `translate-srt.mjs`, men lägger till:

- **Original och översättning sida vid sida.** Varje replik visas med nummer,
  tidkod, engelsk text och svensk text. Den svenska texten kan redigeras direkt.
  En CPS-etikett (tecken per sekund) blir orange eller röd när en replik är för
  lång, och en ikon visar när en rad är längre än max radlängd.
- **Frågor när Claude är osäker.** Claude översätter alltid med sitt bästa
  förslag, men kan ställa frågor om t.ex. du eller ni, talarens kön, ordlekar
  eller återkommande begrepp. Du väljer själv hur frågorna ska hanteras:
  - *Pausa och fråga direkt* (standard). Översättningen stannar, du svarar,
    och batchen översätts om med ditt svar.
  - *Samla frågor.* Översättningen fortsätter och frågorna samlas i
    sidopanelen. När du svarar översätts de berörda replikerna om.
  - *Fråga aldrig.*

  Dina svar gäller resten av översättningen, och du kan välja att spara dem i
  seriens prompt.
- **Promptbibliotek per serie eller film.** Claude kan skapa en prompt för ett
  verk, med stilguide, karaktärer, ordlista och anteckningar. Den kan använda
  webbsökning och repliker ur den inlästa filen som underlag. Promptarna sparas
  och hittas automatiskt via filnamnet nästa gång. Till exempel matchar
  `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` den sparade prompten
  för *All Creatures Great and Small*. Du kan också lägga till alias.
- **Uppdatering av prompten.** Under översättningen noterar Claude nya
  karaktärer, termer och iakttagelser som inte redan finns i prompten. När
  översättningen är klar frågar appen om prompten ska uppdateras, och du
  bockar i vad som ska sparas.

## Språk

- Välj **Från** och **Till** i raden ovanför replikerna (eller i Inställningar).
  Ett 30-tal språk finns, bl.a. svenska, norska, danska, finska, engelska,
  tyska, franska, spanska, italienska, polska, japanska och kinesiska.
- **Från: Automatiskt** känner igen originalets språk med macOS inbyggda
  språkigenkänning (NaturalLanguage – offline och gratis). Är texten tvetydig
  används filnamnet (`_en`, `.ger`, `.French` …). Upptäckt språk och hur säker
  igenkänningen är visas bredvid språkvalet.
- Grundstilen är språkneutral; varje målspråk har egna regler (du/ni,
  du/Sie, tu/vous, fransk typografi, spanska ¿¡ …).
- Varje prompt har ett målspråk och hittas automatiskt bara när du översätter
  till det språket. Finns en prompt för samma serie på ett annat språk kan du
  använda den ändå, eller låta Claude skapa en version för det nya språket med
  den gamla som underlag.
- Det sparade filnamnet får målspråkets kod: `Show_en.srt` → `Show_de.srt`.

## Granska en undertextfil

**Granska** i sidofältet (eller ⌥⌘O) kontrollerar vilken `.srt`-fil som helst,
på vilket språk som helst. Det går också att granska en översättning direkt
med knappen **Granska** i översättningsvyn.

**Tekniska kontroller** körs direkt, lokalt och gratis:

| Kategori | Kontrolleras |
|---|---|
| Tidkoder | otolkbara tidkoder, slut före start, överlapp med nästa replik (kan rättas), fel ordning, för kort (< 0,7 s) eller för lång (> 7 s) visningstid |
| Numrering | hopp och dubbletter (kan numreras om) |
| Radlängd / läshastighet | fler än 2 rader, för långa rader, för hög CPS |
| Formatering | tomma repliker, dubbla mellanslag, mellanslag i början/slutet, obalanserade `<i>`/`<b>`/`<u>`-taggar |
| Interpunktion | mellanslag före skiljetecken (utom franska ! ? : ;), saknat mellanslag efter, parenteser och citattecken som inte går jämnt ut, liten bokstav efter avslutad mening |
| Konsekvens | blandat `...`/`…`, blandade dialogstreck (`-`, `- `, `– `) |
| Stavning | upprepade ord (”att att”) |

**Granska språket** låter Claude gå igenom stavning, grammatik,
interpunktion, ordval, konsekvens (t.ex. namn som stavas olika) och repliker
som inte går att förstå. Om en sparad prompt matchar filen används dess
ordlista för namn och termer.

Varje anmärkning visar ett förslag där borttagen text är röd och ny text är
grön. Välj **Åtgärda** eller **Ignorera**, eller **Åtgärda alla** för alla
tekniska rättningar eller alla Claudes förslag. Repliker kan också redigeras
direkt och återställas till originalet. **Spara** skriver den rättade filen.

## Krav

- macOS 14 (Sonoma) eller senare
- Fullständiga Xcode 15 eller senare (Command Line Tools räcker inte – SwiftUI:s makron, t.ex. `@State`, finns bara i Xcode)
- En API-nyckel från [console.anthropic.com](https://console.anthropic.com)

## Bygga och starta

Snabbast, direkt från terminalen:

```bash
cd Undertextaren
swift run -c release
```

Bygg en riktig `.app` som kan läggas i Program-mappen:

```bash
./build-app.sh
open build/Undertextaren.app
```

Eller öppna paketet i Xcode och tryck ⌘R:

```bash
open Package.swift
```

Första gången: öppna **Inställningar (⌘,)** och klistra in API-nyckeln. Den
sparas i macOS-nyckelringen. Appen läser också miljövariabeln
`ANTHROPIC_API_KEY` om den finns.

## API-nyckeln och nyckelringen

Nyckeln sparas i macOS-nyckelringen (posten *Undertextaren* i
Nyckelhanteraren) och läses därifrån vid varje start. Nyckelringen släpper
bara fram nyckeln till samma app som sparade den, och "samma app" avgörs av
kodsigneringen. Därför signerar `build-app.sh` med ett utvecklarcertifikat om
ett sådant finns:

1. Öppna Xcode → **Inställningar → Konton** och lägg till ditt Apple-ID
   (ett gratis konto räcker).
2. Välj kontot → **Hantera certifikat… → + → Apple Development**.
3. Bygg med `./build-app.sh`. Det står `✓ Signerad med: Apple Development …`.
4. Lägg in API-nyckeln en sista gång. Frågar macOS om åtkomst till
   nyckelringen, välj **Tillåt alltid**.

Utan certifikat ad hoc-signeras appen, och då kan nyckeln behöva läggas in
igen efter varje bygge. Om du har flera certifikat kan du välja ett med
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## Så används den

1. Öppna eller släpp en engelsk `.srt` i fönstret (⌘O).
2. Appen gissar titel och avsnitt ur filnamnet och letar efter en sparad
   prompt. Om ingen finns kan du klicka **Skapa med Claude…**.
3. Tryck **Översätt** (⌘R). Du kan stoppa och fortsätta senare. Då
   översätts bara de repliker som saknar översättning.
4. Granska resultatet. Använd filtren *Frågor*, *För långa*, *Redigerade* och
   *Fel*. Högerklicka på en replik för att översätta om den.
5. Spara (⌘S). Språkkoden i filnamnet byts mot målspråkets:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, annars `.srt` → `.sv.srt`.

## Inställningar

| Inställning | Standard | Motsvarar i skriptet |
|---|---|---|
| Modell | `claude-opus-5-5` | `MODEL` |
| Repliker per anrop | 20 | `BATCH_SIZE` |
| Kontext (tidigare repliker) | 4 | `CONTEXT` |
| Max tecken/sekund | 17 | `MAX_CPS` |
| Max tecken per rad | 42 | `MAX_LINE_LEN` |
| Grundstil | skriptets `DEFAULT_STYLE` | `STYLE_FILE` (kan läsas in från fil) |

Du kan också välja *Ansträngning (effort)* och om en reservmodell ska användas
när en förfrågan avböjs (server-side fallback). Sonnet 5.5 och Haiku 5.5 är
billigare alternativ till Opus 5.5.

## Importera befintliga prompter

Har du redan stilguider, t.ex. de `.md`/`.txt`-filer du använt med
`STYLE_FILE` i skriptet, kan du importera dem:

- **Arkiv → Importera prompter… (⇧⌘I)**, knappen i sidofältet, eller släpp
  filerna på sidofältet. Flera filer går bra på en gång.
- Titeln gissas ur filnamnet (`little-house-on-the-prairie_stil.md` →
  *Little House On The Prairie*) och kan ändras innan import. Titeln är det
  som matchas mot undertextfilernas namn, så skriv den som serien heter.
- **Spara som:** ny prompt, eller ersätt/uppdatera en som redan finns.
- **Låt Claude dela upp …** (valfritt): Claude flyttar karaktärer och termer
  till egna listor och lägger resten i stilguiden. Utan bocken importeras
  texten ordagrant som stilguide.
- `.json` som exporterats från Undertextaren (en eller alla prompter)
  importeras som de är.

Exportera med **Exportera** i prompten, högerklick i sidofältet eller
**Arkiv → Exportera alla prompter…**.

## Var sparas promptarna?

`~/Library/Application Support/Undertextaren/profiles.json`. Det är vanlig
JSON som går att säkerhetskopiera eller dela. **Inställningar → Visa i
Finder** öppnar mappen.

## Ikon

Ikonen finns i `Assets/`: `AppIcon.svg` är källan, `AppIcon.icns` används av
`build-app.sh` och `AppIcon-1024.png` är en förhandsvisning. Visar Dock eller
Finder fortfarande den gamla ikonen efter ett bygge, kör
`killall Dock; killall Finder`.

## Kodens upplägg

```
Sources/Undertextaren/
├── UndertextarenApp.swift        appen, menyer, AppModel
├── Core/
│   ├── SRT.swift                 parser/serialiserare, tidkoder, titel ur filnamn
│   ├── Language.swift            språklista, målspråksregler, språkigenkänning
│   ├── SubtitleChecker.swift     tekniska kontroller av en .srt-fil
│   ├── ReviewSession.swift       granskning: anmärkningar, rättningar, Claude-granskning
│   ├── ReviewModels.swift        anmärkningar, kategorier, allvarlighetsgrad
│   ├── TextDiff.swift            ordvis jämförelse för att visa ändringar
│   ├── AnthropicClient.swift     Messages API (rå HTTP), retry/backoff, JSON-tolkning
│   ├── PromptBuilder.swift       grundstil + verksprofil + beslut + svarsformat
│   ├── TranslationSession.swift  översättningsmotor, frågor, förslag
│   ├── PromptLibrary.swift       sparade promptar, matchning mot titel
│   ├── ProfileGenerator.swift    Claude skapar, förbättrar eller strukturerar en prompt
│   ├── PromptImporter.swift      import/export av prompter (.md/.txt/.json)
│   ├── AppSettings.swift         inställningar + nyckelring
│   └── Models.swift              datatyper
└── Views/                        SwiftUI-vyer
```
