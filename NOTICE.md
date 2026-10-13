# NOTICE — which license covers what

English Practice — https://github.com/recepyagmur/EnglishPractice

- **Code** (the application's own code, the logo and icons in app/frontend): MIT License, see `LICENSE`.
- **Content** in `app/content/` (lessons, lesson summaries, exams, patterns, YDS-style questions, word lists): Creative Commons
  Attribution-ShareAlike 4.0 International (CC BY-SA 4.0), full text in `LICENSES/CC-BY-SA-4.0.txt`; sources and
  required attributions in `app/content/LICENSE.md`.
- **Turkish voice model** in `app/tts_tr/` (EMA Lightning by canberk7 / canberkkkkkk, converted to ONNX):
  Apache License 2.0, see `app/tts_tr/LICENSE` (changes described in `app/tts_tr/README.md`).
- **Third-party software and models** downloaded at setup (Python, Ollama, Python packages, Gemma / Qwen,
  Whisper, Kokoro, the Wiktionary dictionary): their own licenses, listed in `README.md`
  ("Kaynaklar, lisanslar ve teşekkürler").

## This fork (enessboz/parla)

Derived from https://github.com/recepyagmur/EnglishPractice (MIT for code, CC BY-SA 4.0 for `app/content/`). Changes made here:
macOS support (setup/bootstrap.sh, setup/hardware.py, setup/installer.py, app/launcher.py, app/backend/config.py),
cloud language models (app/backend/cloud_llm.py + settings UI), long-term conversation memory (app/backend/memory.py),
AI-started conversations and a coaching prompt (app/backend/prompts.py, chat.py), hands-free mode (app/frontend/handsfree.js),
and an experimental native Swift prototype (native-swift/). The original copyright notices and licenses are kept unchanged.
