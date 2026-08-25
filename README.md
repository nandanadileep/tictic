# TicTic: macOS Voice Typing for Indian Languages

TicTic is an open-source, native macOS voice typing and speech-to-text app for Indian languages. Built with SwiftUI and powered by Sarvam AI, it turns speech into text in any Mac app using a global dictation shortcut.

Speak naturally in Hindi, Tamil, Telugu, Kannada, Malayalam, Bengali, Marathi, Gujarati, Indian English, and other Indic languages. TicTic can preserve the original script, transliterate speech into Roman text, translate it to English, or produce code-mixed output.

## Highlights

- Native SwiftUI menu-bar experience with a compact floating waveform
- Hold-to-talk and double-tap hands-free modes
- Automatic language detection plus 23 Indian language choices
- Original-script, English translation, verbatim, transliteration, and code-mix output
- Secure API-key storage in macOS Keychain
- Direct insertion through Accessibility APIs with a paste fallback
- Long dictations automatically split into Sarvam-compatible segments
- Optional app-aware polishing through Sarvam 105B, with five writing styles
- Personal corrections and voice-triggered reusable snippets stored locally
- Local, searchable dictation history; audio is deleted after transcription
- Configurable shortcuts selected to avoid common macOS defaults

## Supported languages

TicTic supports automatic language detection and 23 language choices: Hindi, Bengali, Kannada, Malayalam, Marathi, Odia, Punjabi, Tamil, Telugu, Indian English, Gujarati, Assamese, Urdu, Nepali, Konkani, Kashmiri, Sindhi, Sanskrit, Santali, Manipuri, Bodo, Maithili, and Dogri.

## Requirements

- macOS 14 or later
- Swift 5.9 or later (Xcode 15+ or Command Line Tools)
- A TicTic private-beta access code

## Build and run

```sh
./scripts/build-app.sh
open dist/TicTic.app
```

On first launch, enter the private-beta access code provided by Nandana and grant Microphone and Accessibility permissions. Each code includes five total minutes of dictation. Accessibility access is required to observe the global shortcut and insert text at the cursor.

The default shortcut is **Option-Z (⌥ Z)**. Hold the shortcut while speaking and release to transcribe, or double-tap it to lock recording; press it once more to finish.

## Beta operations

The hosted API lives at `https://tictic-api.vercel.app` and uses Vercel Functions plus Upstash Redis. To create unique five-minute access codes for friends:

```sh
./scripts/create-beta-invites.sh 5 "Friends batch"
```

The admin secret stays in macOS Keychain. Invite codes are shown once by the script; distribute one different code to each person.

## How it works

TicTic records AAC audio locally in 25-second segments and sends each segment through the TicTic Vercel API to Sarvam's `saaras:v3`. The API keeps the shared Sarvam key private and enforces a five-minute lifetime allowance per invite code using Redis. The app joins ordered transcripts, applies local vocabulary, optionally polishes the result with `sarvam-105b`, and inserts it into the app that was active when recording began. Beta access codes live in Keychain, preferences and transcript history stay on-device, and temporary audio files are removed after each request.

## Privacy

Audio passes through the TicTic API and is forwarded to Sarvam AI for transcription. The API stores only a hashed invite-code identifier and the number of milliseconds used; it does not persist audio or transcripts and runs no analytics. Transcript history stays on the Mac and can be disabled or cleared from Settings.

## Project status

This repository contains a functional macOS MVP. Code signing, notarization, automatic updates, and App Store distribution credentials are intentionally left to the repository owner.
