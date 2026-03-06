# chunktts

Turn marked-up stdin text into numbered `.wav` files with DeepInfra's
OpenAI-compatible Kokoro TTS endpoint.

`chunktts` is built for shell pipelines. Feed it text that already contains
split markers like `<break>`, and it will:

- split the input into chunks
- send chunks in parallel with a bounded `max_inflight` limit
- retry transient API failures
- validate each returned WAV with `libsndfile`
- write deterministic `0001.wav`, `0002.wav`, ... files

## Why try it?

- Stdin-first workflow: no input file format to invent, just pipe text in.
- Minimal surface area: one required CLI argument, a tiny `config.json`, and no
  extra operational flags.
- Bounded parallelism: uses the same Relay-based max-inflight pattern as
  `pdfocr`, so it scales without unbounded request bursts.
- Safer audio output: every generated WAV is reopened through `libsndfile`
  before it becomes a final output file.

## Quick Start

Build:

```bash
atlas install
nim c -d:release -o:chunktts src/app.nim
```

Run:

```bash
export DEEPINFRA_API_KEY=...
printf 'First chunk.<break>Second chunk.<break>Third chunk.\n' | ./chunktts out
```

Output:

```text
out/
  0001.wav
  0002.wav
  0003.wav
```

## What the input should look like

`chunktts` reads all text from `stdin` and splits on a marker string.
The default marker is `<break>`.

Example:

```text
Introduction paragraph.<break>
This should become the second audio file.<break>
Closing section.
```

Whitespace around each chunk is trimmed. Empty chunks are dropped, so repeated
markers like `<break><break>` do not create empty WAV files.

## CLI

```bash
./chunktts OUT_DIR < input.txt
./chunktts --help
```

That is the full CLI.

- `OUT_DIR` is required.
- Input always comes from `stdin`.
- `stdout` is unused during normal operation.
- Logs and fatal errors go to `stderr`.

## Config

Optional `config.json` next to the executable can override the most important
runtime settings:

```json
{
  "break_marker": "<break>",
  "voice": "af_bella",
  "speed": 1.0,
  "max_inflight": 32
}
```

Supported keys:

- `api_key`: fallback API key if `DEEPINFRA_API_KEY` is not set
- `break_marker`: exact string used to split stdin
- `voice`: Kokoro voice name
- `speed`: playback speed, clamped to the supported range
- `max_inflight`: maximum number of concurrent in-flight TTS requests

Environment precedence:

- `DEEPINFRA_API_KEY` overrides `config.json.api_key`

Built-in defaults:

- endpoint: `https://api.deepinfra.com/v1/openai/audio/speech`
- model: `hexgrad/Kokoro-82M`
- marker: `<break>`
- voice: `af_bella`
- speed: `1.0`
- max inflight: `32`

## Installation

### From source

Linux:

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev libsndfile1-dev
atlas install
nim c -d:release -o:chunktts src/app.nim
```

macOS:

```bash
brew install curl libsndfile
atlas install
nim c -d:release -o:chunktts src/app.nim
```

Windows:

- install Nim
- install Atlas
- install `curl` and `libsndfile` through `vcpkg`
- build with:

```powershell
atlas install
nim c -d:release -o:chunktts.exe src/app.nim
```

### Prebuilt binaries

GitHub release archives are produced by
[release.yml](/home/ageralis/chunktts/.github/workflows/release.yml).

Linux and macOS builds still rely on system `libcurl` and `libsndfile`
runtime libraries. Windows release archives bundle the required DLLs.

## Exit Codes

- `0`: all chunks succeeded
- `2`: at least one chunk failed after retries
- `3`: fatal startup or runtime failure

## Practical Workflow

Preprocess text with another tool, insert `<break>` markers where you want
audio boundaries, then hand the result to `chunktts`:

```bash
cat marked_script.txt | ./chunktts wav_out
```

If your upstream step emits a different marker, set it in `config.json` and
keep the CLI unchanged.

## Verification

Run the local test suite:

```bash
nim test tests/ci.nims
```

This includes:

- chunk-splitting behavior
- request-id packing
- retry/error classification
- `libsndfile` wrapper validation
- OpenAI speech request construction
- an integration test that checks retry handling and real `max_inflight`
  behavior against a local stub server
