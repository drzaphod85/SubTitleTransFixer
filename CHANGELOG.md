# Changelog

All notable changes to SubTitle TransFixer. Versions follow
[Semantic Versioning](https://semver.org); the newest version is at the top.

## [Unreleased]

### Added
- Open subtitle files by dragging them onto the window or the Dock icon, with
  **Open With** in Finder, or with a double-click. A frame shows where a
  dropped file will go. Files opened from Finder are reviewed if they are
  already in the target language, otherwise translated.
- Videos dropped on *Review* are used as the review's video.

## [1.0.0] – 2026-11-06

The first public version.

### Translate
- Translates `.srt` subtitles between languages with Claude, with the original
  and the translation shown side by side.
- Detects the language of the original automatically (from the text and the
  file name, e.g. `.sv.srt`).
- Asks you when it is unsure about a name, a term or a line.
- Creates a prompt per TV series or film, saves it and picks it again when the
  series comes back. Offers to update the prompt with new characters and facts.
- Imports prompts you already have.

### Review
- Checks a subtitle file for numbering, timing, line length, reading speed,
  spacing, punctuation, tags, quotes and other common errors, with automatic
  fixes for most of them.
- Compares the file with the original subtitle.
- Lets Claude review the language with the same prompt as the translation.
- Accept all suggestions at once, undo/redo, Save, Save As and Cancel. A `.bak`
  copy is kept the first time a file is saved.

### Video
- Finds the video with the same name next to the subtitle and plays from five
  seconds before to five seconds after a line.
- Suggests better start and end times from the audio and checks the whole file
  against the speech.

### Other
- The interface is in English, Swedish, Norwegian, Danish, Finnish and Icelandic.
- The API key is stored in the macOS keychain.
- Universal app for Apple silicon and Intel, signed with Developer ID and
  notarized by Apple.
