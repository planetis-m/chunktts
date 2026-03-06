version       = "0.1.0"
author        = "ageralis"
description   = "Chunk marked-up text files into one Kokoro TTS opus file"
license       = "AGPL-3.0-only"
srcDir        = "src"
bin           = @["chunktts"]

requires "nim >= 2.2.8"
requires "https://github.com/planetis-m/mimalloc_nim"
requires "https://github.com/planetis-m/jsonx"
requires "https://github.com/planetis-m/relay"
requires "https://github.com/planetis-m/openai"
