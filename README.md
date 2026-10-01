# Kokoro TTS for iOS

Spike: free, open-source, **on-device** neural text-to-speech on iPhone.

- Engine: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache 2.0) via its official Swift package — no build-from-source needed
- Voices: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) v1.0, int8 quantized (`csukuangfj/kokoro-int8-multi-lang-v1_0`), 54 voices, 24 kHz
- The model (~165 MB) downloads once from Hugging Face on first launch, then everything runs offline — no API keys, no cloud, no subscription

## Status

🚧 Spike — validates voice quality on a real iPhone before integrating into the Zotero read-aloud fork.

## Build

Pushing to `main`/`master` builds an unsigned IPA via GitHub Actions (macOS runner, Xcode 26 if available).
