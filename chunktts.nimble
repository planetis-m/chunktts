version       = "0.2.0"
author        = "planetis"
description   = "Generate one Opus speech file from marked-up text with Kokoro TTS"
license       = "AGPL-3.0"
srcDir        = "src"
bin           = @["app"]

requires "nim >= 2.2.8"
requires "https://github.com/planetis-m/mimalloc_nim"
requires "https://github.com/planetis-m/jsonx"
requires "https://github.com/planetis-m/relay"
requires "https://github.com/planetis-m/openai"
