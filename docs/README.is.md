# SubTitle TransFixer

Mac-forrit (Swift + SwiftUI) sem **þýðir** `.srt`-skjátexta milli tungumála
með Claude og **yfirfer** skjátextaskrár með tilliti til tæknilegra villna og málvillna.
Það byrjaði sem skriftan `translate-srt.mjs` (enska → sænska) og hét
áður *Undertextaren*.

Lesa á: [English](../README.md) · [Svenska](README.sv.md) · [Norsk](README.nb.md) ·
[Dansk](README.da.md) · [Suomi](README.fi.md) · **Íslenska**

## Eiginleikar

- **Frumtexti og þýðing hlið við hlið.** Hver skjátexti er sýndur með
  númeri, tímakóða, frumtexta og þýðingu, og hægt er að breyta þýðingunni
  beint. CPS-merki (stafir á sekúndu) verður appelsínugult eða rautt þegar
  skjátexti er of langur, og tákn sýnir línur sem eru lengri en hámarkið.
- **Hvaða tungumálapar sem er.** Um 30 tungumál, valin sem *Frá* og *Til* fyrir ofan
  skjátextana. Með *Frá: Sjálfvirkt* er tungumál frumtextans greint
  með innbyggðri tungumálagreiningu macOS (án nettengingar og ókeypis), með vísbendingum
  úr skráarheitinu (`_en`, `.ger`, `.French` …) þegar textinn er tvíræður.
- **Spurningar þegar Claude er óviss.** Claude þýðir alltaf með bestu
  tillögu sinni en getur spurt um formlegt eða óformlegt ávarp, kyn þess sem
  talar, orðaleiki eða endurtekin hugtök. Veldu hvernig spurningar eru meðhöndlaðar:
  *gera hlé og spyrja strax* (lotan er þá þýdd aftur með svari
  þínu), *safna spurningum* í hliðarspjaldinu eða *spyrja aldrei*. Svörin gilda
  fyrir afganginn af keyrslunni og hægt er að vista þau í kvaðningu þáttaraðarinnar.
- **Kvaðningasafn fyrir hverja þáttaröð eða kvikmynd.** Claude getur búið til kvaðningu fyrir
  verk – stílleiðbeiningar, persónur, orðalista og minnispunkta – ef vill með vefleit
  og skjátextum úr opnu skránni. Kvaðningar eru vistaðar og finnast
  sjálfkrafa út frá skráarheitinu næst, t.d. finnur
  `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` kvaðninguna fyrir
  *All Creatures Great and Small*. Hver kvaðning hefur markmál; kvaðningu
  fyrir annað tungumál má nota samt eða hafa sem grunn að nýrri.
- **Kvaðningin heldur áfram að læra.** Meðan á þýðingu stendur skráir Claude nýjar
  persónur, hugtök og athuganir. Þegar þýðingunni er lokið spyr forritið
  hvort uppfæra eigi kvaðninguna og þú hakar við það sem á að halda.
- **Innflutningur og útflutningur kvaðninga.** Flyttu inn fyrirliggjandi stílleiðbeiningar (`.md`/`.txt`,
  t.d. skrár sem notaðar eru með `STYLE_FILE` í skriftunni) eða `.json`-útflutning.
  Claude getur ef vill skipt texta í stílleiðbeiningar, persónur og
  orðalista.
- **Yfirferð.** Athugar hvaða `.srt`-skrá sem er á hvaða tungumáli sem er – sjá hér að neðan.
- **Viðmót á sex tungumálum:** ensku, sænsku, norsku (bókmáli),
  dönsku, finnsku og íslensku. Forritið fylgir tungumáli macOS eða
  valinu undir *Stillingar → Tungumál forritsins*. Claude skrifar spurningar sínar og
  athugasemdir á sama tungumáli.

## Yfirfara skjátextaskrá

**Yfirfara** í hliðarstikunni (eða ⌥⌘O) athugar hvaða `.srt`-skrá sem er. Einnig er hægt að
yfirfara þýðingu beint með hnappnum **Yfirfara** í þýðingaryfirlitinu.

**Tæknilegar athuganir** keyra á tölvunni sjálfri, samstundis og án endurgjalds:

| Flokkur | Athugað |
|---|---|
| Tímakóðar | tímakóðar sem ekki er hægt að túlka, lok á undan upphafi, skörun við næsta skjátexta (hægt að laga), röng röð, of stuttur (< 0,7 s) eða of langur (> 7 s) birtingartími |
| Númering | göt og tvítekningar (hægt að endurnúmera) |
| Línulengd / leshraði | fleiri en 2 línur, of langar línur, of hátt CPS |
| Snið | tómir skjátextar, tvöföld bil, bil í upphafi/lok, ójöfn `<i>`/`<b>`/`<u>`-merki |
| Greinarmerki | lína sem byrjar t.d. á `!`, `&` eða `,`; bil á undan greinarmerki (nema franskt ! ? : ;); bil vantar á eftir (tvípunktur inni í orðum eins og `1:a`, `S:t`, `TV:n` er leyfður); svigar og gæsalappir sem passa ekki saman; lágstafur á eftir lokinni setningu |
| Samræmi | blandað `...`/`…`, blönduð samtalsstrik (`-`, `- `, `– `) |
| Stafsetning | endurtekin orð („og og“) |

**Yfirfara málfar** lætur Claude athuga stafsetningu, málfræði, greinarmerki, orðalag,
samræmi (t.d. nöfn sem eru stafsett á mismunandi vegu) og skjátexta sem erfitt er að
skilja. **Yfirferðin notar sömu kvaðningu og þýðingin**: grunnstílinn,
reglur markmálsins og verksniðið með stílleiðbeiningum sínum,
persónum, orðalista og vistuðum ákvörðunum. Leiðréttingar fylgja því
reglum þáttaraðarinnar um ávarp, tón og nöfn, og frávik frá
kvaðningunni eru tilkynnt.

### Bera saman við frumtextann

- Úr þýðingaryfirlitinu er frumtextinn þegar tengdur.
- Þegar þú opnar skrá leitar forritið að frumtextanum í sömu möppu
  (`Show_sv.srt` → `Show_en.srt`, `Show.en.srt`, `Show.srt` …), eða þú velur hann
  með **Bera saman við frumskrá…**.
- Skjátextar eru paraðir saman eftir tímakóðum, svo þetta virkar jafnvel þegar frumtextinn
  og þýðingin skipta skjátextum á ólíkan hátt. Frumtextinn er sýndur
  fyrir ofan hvern skjátexta.

Á tölvunni sjálfri finnur samanburðurinn skjátexta í frumtextanum sem vantar í
þýðinguna (og öfugt), skáletur sem hefur glatast og ártöl, upphæðir og
tíma sem hafa breyst eða horfið. Með **Yfirfara og bera saman** athugar Claude einnig
rangþýðingar, efni sem var fellt út eða bætt við, nöfn, tölur,
neitanir og ávarp. Venjuleg stytting er ekki talin villa.

Hver athugasemd sýnir tillögu þar sem fjarlægður texti er rauður og nýr texti grænn.
Veldu **Laga** eða **Hunsa**, eða **Laga allt** fyrir allar tæknilegar lagfæringar eða allar
tillögur Claude. Hægt er að breyta skjátextum beint og færa þá aftur í upprunalegt
horf. **Vista** skrifar leiðréttu skrána.

## Kröfur

- macOS 14 (Sonoma) eða nýrra
- Fullt Xcode 15 eða nýrra (Command Line Tools duga ekki – fjölvar SwiftUI,
  eins og `@State`, fylgja aðeins Xcode)
- API-lykill frá [console.anthropic.com](https://console.anthropic.com)

## Byggja og keyra

Byggðu raunverulegt `.app` sem hægt er að setja í Forritamöppuna:

```bash
./build-app.sh
```

```bash
open "build/SubTitle TransFixer.app"
```

Eða opnaðu pakkann í Xcode og ýttu á ⌘R:

```bash
open Package.swift
```

Í fyrsta skipti: opnaðu **Stillingar (⌘,)** og límdu inn API-lykilinn. Hann er geymdur í
lyklakippu macOS. Forritið les einnig umhverfisbreytuna `ANTHROPIC_API_KEY`
ef hún er skilgreind.

### Flutt frá Undertextaren

Við fyrstu ræsingu eru stillingar, vistaðar kvaðningar og API-lykillinn afritaðar úr
*Undertextaren*. Engu er eytt, svo gamla forritið virkar áfram.

## API-lykillinn og lyklakippan

Lykillinn er geymdur í lyklakippu macOS (færslan *SubTitle TransFixer* í
Lyklakippu) og lesinn þaðan við hverja ræsingu. Lyklakippan lætur lykilinn
aðeins af hendi við sama forrit og vistaði hann, og hvað telst „sama forritið“ ræðst
af kóðaundirrituninni. Þess vegna undirritar `build-app.sh` með forritaraskírteini
þegar það er til staðar:

1. Opnaðu Xcode → **Settings → Accounts** og bættu við Apple ID-auðkenninu þínu (ókeypis aðgangur dugar).
2. Veldu aðganginn → **Manage Certificates… → + → Apple Development**.
3. Byggðu með `./build-app.sh`. Það prentar `✓ Signed with: Apple Development …`.
4. Sláðu inn API-lykilinn í síðasta sinn. Ef macOS biður um aðgang að lyklakippunni skaltu velja **Always Allow** (Leyfa alltaf).

Án skírteinis er forritið undirritað ad hoc og gæti þurft að slá lykilinn
inn aftur eftir hverja byggingu. Ef skírteinin eru fleiri en eitt skaltu velja eitt með
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## Notkun

1. Opnaðu skjátextaskrá eða slepptu henni í gluggann (⌘O).
2. Athugaðu *Frá* og *Til*. Forritið giskar á titil og þátt út frá
   skráarheitinu og leitar að vistaðri kvaðningu. Ef engin er til skaltu smella á **Búa til með Claude…**.
3. Ýttu á **Þýða** (⌘R). Þú getur stöðvað og haldið áfram síðar; aðeins skjátextar
   án þýðingar eru þýddir.
4. Athugaðu niðurstöðuna með síunum *Spurningar*, *Of langt*, *Breytt* og
   *Mistókst*. Hægrismelltu á skjátexta til að þýða hann aftur.
5. Ýttu á **Yfirfara** til að athuga þýðinguna, eða **Vista** (⌘S). Tungumálakóðanum
   í skráarheitinu er skipt út fyrir kóða markmálsins:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, annars `.srt` → `.sv.srt`.

## Stillingar

| Stilling | Sjálfgefið | Í upprunalegu skriftunni |
|---|---|---|
| Tungumál forritsins | Sama og macOS | – |
| Líkan | `claude-opus-5-5` | `MODEL` |
| Þýða úr / á | Sjálfvirkt / sænska | – |
| Skjátextar í hverri beiðni | 20 | `BATCH_SIZE` |
| Samhengi (fyrri skjátextar) | 4 | `CONTEXT` |
| Hám. stafir á sekúndu | 17 | `MAX_CPS` |
| Hám. stafir í línu | 42 | `MAX_LINE_LEN` |
| Grunnstíll | sjálfgefinn, óháður tungumáli | `STYLE_FILE` (hægt að hlaða úr skrá) |

Þú getur einnig valið *Fyrirhöfn* og hvort varalíkan sé notað þegar
beiðni er hafnað (varaleið á þjóni). Sonnet 5.5 og Haiku 5.5 eru
ódýrari kostir en Opus 5.5.

Grunnstíllinn notar staðgenglana `{SOURCE_LANGUAGE}`, `{TARGET_LANGUAGE}`,
`{TARGET_RULES}` (eigin reglur markmálsins, t.d. du/ni eða du/Sie),
`{MAX_LINE_LEN}` og `{MAX_CPS}`. Grunnstíl sem þú breyttir aldrei í
eldri útgáfu er sjálfkrafa skipt út fyrir nýja sjálfgefna stílinn.

## Hvar eru kvaðningarnar geymdar?

`~/Library/Application Support/SubTitle TransFixer/profiles.json` – venjulegt JSON
sem hægt er að taka afrit af eða deila. **Stillingar → Sýna í Finder** opnar möppuna.

## Staðfærsla

Allir textar sem notandinn sér eru skrifaðir á ensku í kóðanum og vafðir inn í
`L("…")`; enski textinn er lykillinn. Staðgenglar eru skrifaðir `{0}`, `{1}` …
Þýðingarnar eru í `Sources/SubTitleTransFixer/Localization/Strings+<code>.swift`
og eru búnar til úr JSON:

```bash
python3 scripts/localization.py extract > strings.json
```

```bash
python3 scripts/localization.py generate localization/sv.json
```

```bash
python3 scripts/localization.py check
```

`check` tilkynnir þýðingar sem vantar, staðgengla sem eru ólíkir og tvítekna
lykla (tvítekinn lykill myndi láta forritið hrynja við ræsingu).

## Tákn

Táknið er í `Assets/`: `AppIcon.svg` er frumskráin, `AppIcon.icns` er
notað af `build-app.sh` og `AppIcon-1024.png` er forskoðun. Ef Dock eða
Finder sýnir enn gamla táknið eftir byggingu skaltu keyra `killall Dock; killall Finder`.

## Uppbygging kóðans

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
