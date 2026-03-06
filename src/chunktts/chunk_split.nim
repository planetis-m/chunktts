import std/strutils

proc splitChunks*(text, marker: string): seq[string] =
  if marker.len == 0:
    raise newException(ValueError, "break marker must not be empty")

  for part in text.split(marker):
    let chunk = part.strip()
    if chunk.len > 0:
      result.add(chunk)
