# Undertextaren

En Mac-app (Swift + SwiftUI) som översätter `.srt`-undertexter från engelska
till svenska med Claude. Den bygger på samma logik och stilguide som
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

## Så används den

1. Öppna eller släpp en engelsk `.srt` i fönstret (⌘O).
2. Appen gissar titel och avsnitt ur filnamnet och letar efter en sparad
   prompt. Om ingen finns kan du klicka **Skapa med Claude…**.
3. Tryck **Översätt** (⌘R). Du kan stoppa och fortsätta senare. Då
   översätts bara de repliker som saknar översättning.
4. Granska resultatet. Använd filtren *Frågor*, *För långa*, *Redigerade* och
   *Fel*. Högerklicka på en replik för att översätta om den.
5. Spara (⌘S). Filnamnet följer skriptets regel: `_en.srt` → `_sv.srt`,
   `.en.srt` → `.sv.srt`, annars `.srt` → `.sv.srt`.

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

## Var sparas promptarna?

`~/Library/Application Support/Undertextaren/profiles.json`. Det är vanlig
JSON som går att säkerhetskopiera eller dela. **Inställningar → Visa i
Finder** öppnar mappen.

## Kodens upplägg

```
Sources/Undertextaren/
├── UndertextarenApp.swift        appen, menyer, AppModel
├── Core/
│   ├── SRT.swift                 parser/serialiserare, tidkoder, titel ur filnamn
│   ├── AnthropicClient.swift     Messages API (rå HTTP), retry/backoff, JSON-tolkning
│   ├── PromptBuilder.swift       grundstil + verksprofil + beslut + svarsformat
│   ├── TranslationSession.swift  översättningsmotor, frågor, förslag
│   ├── PromptLibrary.swift       sparade promptar, matchning mot titel
│   ├── ProfileGenerator.swift    Claude skapar eller förbättrar en prompt
│   ├── AppSettings.swift         inställningar + nyckelring
│   └── Models.swift              datatyper
└── Views/                        SwiftUI-vyer
```
