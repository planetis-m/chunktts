# chunktts

`chunktts` reads marked-up text from stdin, splits it into chunks, sends each chunk
through DeepInfra's OpenAI-compatible Kokoro TTS endpoint, and writes numbered
`.wav` files to an output directory.

## Usage

```bash
./chunktts OUT_DIR < input.txt
```

Input is split by the configured marker, which defaults to `<break>`.

## Config

Optional `config.json` next to the executable may define:

- `api_key`
- `break_marker`
- `voice`
- `speed`
- `max_inflight`

`DEEPINFRA_API_KEY` overrides `api_key`.
