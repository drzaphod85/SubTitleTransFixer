# SubTitle TransFixer

A Mac app (Swift + SwiftUI) that **translates** `.srt` subtitles between languages
with Claude and **reviews** subtitle files for technical and language errors.
It started out as the script `translate-srt.mjs` (English → Swedish) and was
previously called *Undertextaren*.

Read this in: **English** · [Svenska](docs/README.sv.md) · [Norsk](docs/README.nb.md) ·
[Dansk](docs/README.da.md) · [Suomi](docs/README.fi.md) · [Íslenska](docs/README.is.md)

## Features

- **Original and translation side by side.** Every subtitle is shown with its
  number, timecode, original text and translation, and the translation can be
  edited directly. A CPS badge (characters per second) turns orange or red when
  a subtitle is too long, and an icon shows lines longer than the maximum.
- **Any language pair.** About 30 languages, chosen as *From* and *To* above
  the subtitles. With *From: Automatic* the original's language is detected
  with macOS's built-in language recognition (offline and free), with hints
  from the file name (`_en`, `.ger`, `.French` …) when the text is ambiguous.
- **Questions when Claude is unsure.** Claude always translates with its best
  suggestion but may ask about formal or informal address, the speaker's
  gender, puns or recurring terms. Choose how questions are handled:
  *pause and ask right away* (the batch is then translated again with your
  answer), *collect questions* in the side panel, or *never ask*. Answers apply
  to the rest of the run and can be saved in the series' prompt.
- **A prompt library per series or film.** Claude can create a prompt for a
  work – style guide, characters, glossary and notes – optionally using web
  search and lines from the loaded file. Prompts are saved and found
  automatically from the file name the next time, e.g.
  `All.Creatures.Great.and.Small.S03E02.1080p.WEB.en.srt` finds the prompt for
  *All Creatures Great and Small*. Each prompt has a target language; a prompt
  for another language can be used anyway or serve as the basis for a new one.
- **The prompt keeps learning.** During translation Claude notes new
  characters, terms and observations. When the translation is done the app
  asks whether the prompt should be updated, and you tick what to keep.
- **Import and export of prompts.** Import existing style guides (`.md`/`.txt`,
  e.g. files used with `STYLE_FILE` in the script) or `.json` exports.
  Claude can optionally split a text into style guide, characters and
  glossary.
- **Review.** Checks any `.srt` file in any language – see below.
- **Interface in six languages:** English, Swedish, Norwegian (Bokmål),
  Danish, Finnish and Icelandic. The app follows the macOS language or the
  choice under *Settings → App language*. Claude writes its questions and
  comments in the same language.

## Review a subtitle file

**Review** in the sidebar (or ⌥⌘O) checks any `.srt` file. A translation can
also be reviewed directly with the **Review** button in the translation view.

**Technical checks** run locally, instantly and free of charge:

| Category | Checked |
|---|---|
| Timecodes | unparsable timecodes, end before start, overlap with the next subtitle (can be fixed), wrong order, too short (< 0.7 s) or too long (> 7 s) display time |
| Numbering | gaps and duplicates (can be renumbered) |
| Line length / reading speed | more than 2 lines, lines that are too long, CPS that is too high |
| Formatting | empty subtitles, double spaces, leading/trailing spaces, unbalanced `<i>`/`<b>`/`<u>` tags |
| Punctuation | a line starting with e.g. `!`, `&` or `,`; space before punctuation (except French ! ? : ;); missing space after (a colon inside words such as `1:a`, `S:t`, `TV:n` is accepted); brackets and quotation marks that don't match; a lower-case letter after a finished sentence |
| Consistency | mixed `...`/`…`, mixed dialogue dashes (`-`, `- `, `– `) |
| Spelling | repeated words ("the the") |

**Review language** lets Claude check spelling, grammar, punctuation, wording,
consistency (e.g. names spelled differently) and subtitles that are hard to
understand. **The review uses the same prompt as the translation**: the base
style, the target language's rules and the work profile with its style guide,
characters, glossary and saved decisions. Corrections therefore follow the
series' rules for forms of address, tone and names, and deviations from the
prompt are reported.

### Compare with the original

- From the translation view the original is already linked.
- When you open a file the app looks for the original in the same folder
  (`Show_sv.srt` → `Show_en.srt`, `Show.en.srt`, `Show.srt` …), or choose one
  with **Compare with original file…**.
- Subtitles are paired by their timecodes, so it works even when the original
  and the translation split subtitles differently. The original text is shown
  above every subtitle.

Locally, the comparison finds original subtitles that are missing from the
translation (and vice versa), italics that were lost, and years, amounts and
times that changed or disappeared. With **Review and compare**, Claude also
checks mistranslations, content that was dropped or added, names, numbers,
negations and forms of address. Normal condensation is not treated as an error.

### Fixing, undoing and saving

- **Review language with Claude** (or **Review and compare with Claude**) is the
  big button at the top of the review.
- Every issue that can be fixed automatically has a **Fix** button and shows the
  change: removed text in red, new text in green, or the new timecode. Automatic
  fixes exist for overlaps, too short or too long display times, an end time
  before the start time, too high CPS (the subtitle is shown longer when there is
  room before the next one), wrong order (sort by time), numbering, empty
  subtitles (remove), long lines and more than two lines (re-wrap), unclosed tags,
  spaces, punctuation and consistency.
- Issues without an automatic fix only have **Ignore**, and say how to fix them
  yourself: edit the text directly, or click the time to the left of a subtitle
  to edit its timecode.
- **Accept all suggestions** applies every suggestion shown with the current
  filter – both Claude's and the automatic fixes – in one step.
- **Undo** and **Redo** work for every fix, ignored issue and edit.
  **Revert all…** goes back to the file as it was when you opened it.
- Nothing is saved automatically. **Save** (⌘S) writes back to the file you
  opened – the first time, a copy of the original is kept as `<name>.srt.bak` –
  and **Save As…** writes a new file. The app asks before you open another file
  or quit with unsaved changes.

### Play the video and fix the timing

If a video with the same name lies next to the subtitle file – e.g. `Matador - S01E01.mkv` next to `Matador - S01E01.sv.srt` – it is found automatically (or choose one with **Choose video…**).

- **▶** on every subtitle plays from 5 seconds before to 5 seconds after, with the subtitle shown in the picture and a loudness curve below. Click in the curve to jump there.
- Adjust the start and end with ±0.1 s or **Set at the playhead**, or let **Suggest from the audio** find where the speech starts and ends. **Use the times** applies the change (it can be undone).
- **Check timecodes against the audio** analyses the whole episode and suggests new times for subtitles that seem to start or end at the wrong time. Accept them one by one or with **Accept all suggestions**.
- The analysis only measures loudness, so music and sound effects can fool it – play the subtitle before you accept.
- macOS plays `.mp4`, `.m4v` and `.mov` by itself. `.mkv`, `.avi` and other formats need [ffmpeg](https://ffmpeg.org): `brew install ffmpeg`.

## Requirements

- macOS 14 (Sonoma) or later
- Full Xcode 15 or later (the Command Line Tools are not enough – SwiftUI's
  macros, such as `@State`, only ship with Xcode)
- An API key from [console.anthropic.com](https://console.anthropic.com)

## Build and run

Build a real `.app` that can be put in the Applications folder:

```bash
./build-app.sh
```

```bash
open "build/SubTitle TransFixer.app"
```

Or open the package in Xcode and press ⌘R:

```bash
open Package.swift
```

The first time: open **Settings (⌘,)** and paste the API key. It is stored in
the macOS keychain. The app also reads the `ANTHROPIC_API_KEY` environment
variable if it is set.

### Moving from Undertextaren

On first launch, settings, saved prompts and the API key are copied from
*Undertextaren*. Nothing is deleted, so the old app keeps working.

## The API key and the keychain

The key is stored in the macOS keychain (the *SubTitle TransFixer* item in
Keychain Access) and read from there at every launch. The keychain only
releases the key to the same app that saved it, and "the same app" is decided
by the code signature. That is why `build-app.sh` signs with a developer
certificate when one is available:

1. Open Xcode → **Settings → Accounts** and add your Apple ID (a free account is enough).
2. Select the account → **Manage Certificates… → + → Apple Development**.
3. Build with `./build-app.sh`. It prints `✓ Signed with: Apple Development …`.
4. Enter the API key one last time. If macOS asks for keychain access, choose **Always Allow**.

Without a certificate the app is signed ad hoc, and the key may have to be
entered again after every build. With several certificates, choose one with
`SIGN_IDENTITY="Apple Development: …" ./build-app.sh`.

## How to use it

1. Open or drop a subtitle file in the window (⌘O).
2. Check *From* and *To*. The app guesses the title and episode from the file
   name and looks for a saved prompt. If there is none, click **Create with Claude…**.
3. Press **Translate** (⌘R). You can stop and continue later; only subtitles
   without a translation are translated.
4. Check the result with the filters *Questions*, *Too long*, *Edited* and
   *Failed*. Right-click a subtitle to translate it again.
5. Press **Review** to check the translation, or **Save** (⌘S). The language
   code in the file name is replaced with the target language's:
   `_en.srt` → `_sv.srt`, `.eng.srt` → `.sv.srt`, otherwise `.srt` → `.sv.srt`.

## Settings

| Setting | Default | In the original script |
|---|---|---|
| App language | Same as macOS | – |
| Model | `claude-opus-5-5` | `MODEL` |
| Translate from / into | Automatic / Swedish | – |
| Subtitles per request | 20 | `BATCH_SIZE` |
| Context (earlier subtitles) | 4 | `CONTEXT` |
| Max characters/second | 17 | `MAX_CPS` |
| Max characters per line | 42 | `MAX_LINE_LEN` |
| Base style | language-neutral default | `STYLE_FILE` (can be loaded from a file) |

You can also choose the *Effort* and whether a fallback model is used when a
request is declined (server-side fallback). Sonnet 5.5 and Haiku 5.5 are
cheaper alternatives to Opus 5.5.

The base style uses the placeholders `{SOURCE_LANGUAGE}`, `{TARGET_LANGUAGE}`,
`{TARGET_RULES}` (the target language's own rules, e.g. du/ni or du/Sie),
`{MAX_LINE_LEN}` and `{MAX_CPS}`. A base style that you never edited in an
earlier version is replaced with the new default automatically.

## Where are the prompts stored?

`~/Library/Application Support/SubTitle TransFixer/profiles.json` – plain JSON
that can be backed up or shared. **Settings → Show in Finder** opens the folder.

## Localization

Every user-facing string is written in English in the code and wrapped in
`L("…")`; the English text is the key. Placeholders are written `{0}`, `{1}` …
The translations live in `Sources/SubTitleTransFixer/Localization/Strings+<code>.swift`
and are generated from the JSON tables in `localization/<code>.json` (edit those, then regenerate):

```bash
python3 scripts/localization.py extract > strings.json
```

```bash
python3 scripts/localization.py generate localization/sv.json
```

```bash
python3 scripts/localization.py check
```

`check` reports missing translations, placeholders that differ and duplicate
keys (a duplicate key would crash the app at launch).

## Icon

The icon lives in `Assets/`: `AppIcon.svg` is the source, `AppIcon.icns` is
used by `build-app.sh` and `AppIcon-1024.png` is a preview. If the Dock or
Finder still shows the old icon after a build, run `killall Dock; killall Finder`.

## Code layout

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
