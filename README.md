# VoicePrompter

A native macOS teleprompter for voice recording. Import a PDF, and the app
reflows the extracted text into large single-column type and auto-scrolls it at
an adjustable reading pace, with a word-precise karaoke-style highlight parked on
a fixed read line — like Apple Music's synced lyrics, but paced by you rather
than to a recording.

Designed to run on the Mac's own screen (no beam-splitter mirroring).

## Features

- **PDF import** — extracts and reflows text into readable teleprompter type.
- **Pacing highlight** — the current word is highlighted (bright), read words
  stay full-opacity, upcoming words are dimmed.
- **Word-precise centering** — the live word is held on a fixed read line and
  motion is interpolated between words, so it glides instead of jumping.
- **Speed control** — words-per-minute slider (60–300).
- **Transport** — play/pause (spacebar), restart, 5-second rewind.
- **Click-to-seek** — click any word to jump there.
- **Scrubber** — draggable progress bar with elapsed / estimated total time;
  auto-pauses while dragging and resumes on release.
- **Adjustable font size.**

## Requirements

- **macOS 15 (Sequoia)** or later — the deployment target. This is the newest
  macOS a 2019 27" 5K iMac supports.
- **Xcode 16** or later (needed for the file-system-synchronized project format).
- Intel or Apple Silicon — builds a universal binary by default.

## Build & run

1. Open `VoicePrompter.xcodeproj` in Xcode.
2. Select the **VoicePrompter** scheme (auto-created on first open) and a **My Mac**
   run destination.
3. **Signing:** in the target's *Signing & Capabilities* tab, set your Team
   (a free personal Apple ID team is fine) so Xcode can sign it to run locally.
4. Press **⌘R**.

The app is not sandboxed, so the PDF file picker has full read access with no
extra entitlements to configure.

## Usage

1. Click the document button (or the center hint) to open a PDF.
2. Set your reading pace with the WPM slider and font size with the stepper.
3. Press **Space** (or the play button) to start; the highlighted word tracks
   your pace on the read line.
4. **Rewind 5s**, **Restart**, click a word to jump, or drag the scrubber to
   reposition. Changing WPM mid-take keeps your place in the script (the time
   readout is a reading-time estimate, so it re-scales with speed).

## Project layout

```
VoicePrompter/
  VoicePrompterApp.swift   App entry point
  ContentView.swift        Window layout + transport controls
  PrompterView.swift       Scrolling surface, highlight, word-precise offset
  PrompterEngine.swift     Playback clock, speed, rewind, seek, scrub
  ScriptImporter.swift     PDF → paragraphs/words (PDFKit)
  FlowLayout.swift          Line-wrapping layout for word views
  ScrubberBar.swift        Draggable progress bar
```

## How the pacing engine works

Everything is driven off a single value, `position` — a *fractional* word index
equal to `elapsed × wpm / 60`. The highlighted word is `floor(position)`; the
scroll offset places `position` on the read line by interpolating between the
current and next word's measured Y. Rewind subtracts from `position`, seek/scrub
sets it, and speed changes just change how fast it advances — so every control
falls out of one number.

## Roadmap ideas

- Windowed rendering of the word views for very long scripts (whole books).
- Remembering last file, speed, and font-size across launches.
- Vision OCR fallback for image-only (scanned) PDFs.
- Optional recording of the take alongside the prompt.
