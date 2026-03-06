# chunktts

Ordered text-to-speech from marked-up text files to one `.opus` file.

`chunktts` reads text that already contains split markers like `<bk>`,
sends the chunks to DeepInfra's OpenAI-compatible Kokoro TTS endpoint, and
writes one final `.opus` file in deterministic chunk order.

## Core guarantees

- input is one text file, stderr is logs only
- on success: exactly one final `.opus` output file
- final audio order matches the normalized chunk order from the input file
- bounded in-flight network work via `max_inflight`
- retry handling for transient network/API failures
- no partial final artifact on partial failure

## Design

`chunktts` uses the same two-part runtime model as `pdfocr`:

1. `main` thread:
- parses CLI and config
- reads one input text file and splits it into ordered chunks
- schedules retries and preserves output order
- validates chunk audio with `libsndfile`
- writes one final `.opus` file

2. Relay transport thread (inside the Relay client):
- runs HTTP requests via libcurl multi
- keeps up to `K = max_inflight` requests active
- returns completions to the main thread

The public contract is intentionally small: one output path in, one final audio
file out. Any temporary chunk WAV handling is internal only.

## Installation

### Prebuilt binaries

Download a release asset for your platform from:

- <https://github.com/planetis-m/chunktts/releases/latest>

Runtime dependencies:

- Linux: `libcurl` and `libsndfile`
- macOS: `curl` and `libsndfile` (Homebrew)
- Windows: no extra runtime install if the archive bundles the required DLLs

Keep the executable and any bundled runtime libraries in the same directory.

### Build from source

<details>
<summary>Linux x86_64</summary>

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev libsndfile1-dev libsndfile-utils
atlas install
nim c -d:release -o:chunktts src/app.nim
```

</details>

<details>
<summary>macOS arm64</summary>

```bash
brew install curl libsndfile
atlas install
nim c -d:release -o:chunktts src/app.nim
```

</details>

<details>
<summary>Windows x86_64 (PowerShell)</summary>

```powershell
atlas install
nim c -d:release -o:chunktts.exe src/app.nim
```

</details>

## Runtime configuration

Optional `config.json` next to the executable overrides built-in defaults.
If `DEEPINFRA_API_KEY` is set, it overrides `api_key` from `config.json`.

Supported keys:

- `api_key`
- `voice`
- `speed`
- `max_inflight`

Example:

```json
{
  "voice": "af_bella",
  "speed": 1.0,
  "max_inflight": 32
}
```

Built-in defaults:

- endpoint: `https://api.deepinfra.com/v1/openai/audio/speech`
- model: `hexgrad/Kokoro-82M`
- marker: `<bk>`
- voice: `af_bella`
- speed: `1.0`
- max inflight: `32`

## CLI

```bash
./chunktts INPUT.txt OUTPUT.opus
./chunktts --help
```

- `INPUT.txt` and `OUTPUT.opus` are required
- `stdout` is unused during normal operation
- logs and fatal errors go to `stderr`

## Input format

`chunktts` splits the input file on a marker string. The default marker is
`<bk>`.

Example:

```text
Introduction paragraph.<bk>
This should become the second spoken section.<bk>
Closing section.
```

Whitespace around each chunk is trimmed. Empty chunks are dropped, so repeated
markers like `<bk><bk>` do not create silent segments.

## Quick start

```bash
export DEEPINFRA_API_KEY=...
./chunktts input.txt output.opus
```

Typical upstream workflow:

1. generate or preprocess text into a file
2. insert `<bk>` markers where audio boundaries should be
3. run `chunktts INPUT.txt OUTPUT.opus`
4. consume one final `.opus` file

## Exit codes

- `0`: all chunks succeeded
- `2`: at least one chunk failed after retries
- `3`: fatal startup/runtime failure

If any chunk fails after retries, `chunktts` does not publish the final
`.opus` file.

## Requirements

- DeepInfra API key via `DEEPINFRA_API_KEY` or `config.json`
- one marked-up text file containing chunk boundaries
- if building from source: Nim `>= 2.2.8`, Atlas, and platform dev packages for
  `libcurl` and `libsndfile`

## Verification

```bash
nim test tests/ci.nims
```

The test suite covers:

- chunk splitting
- request-id packing
- retry/error classification
- `libsndfile` read/write validation, including direct `.opus` output
- OpenAI speech request construction
- integration coverage for retry handling, ordered concatenation, and
  real `max_inflight` behavior against a local stub server
