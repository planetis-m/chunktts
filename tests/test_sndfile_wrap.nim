import std/[base64, os]
import chunktts/sndfile_wrap

const SampleWavBase64 =
  "UklGRjQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YRAAAAAAAOgDGPz0AQz+AAAAAAAA"

proc main() =
  let tempPath = getTempDir() / "chunktts-test.wav"
  writeFile(tempPath, decode(SampleWavBase64))
  defer:
    if fileExists(tempPath):
      removeFile(tempPath)

  let info = readAudioFileInfo(tempPath)
  doAssert info.sampleRate == 8000
  doAssert info.channels == 1
  doAssert info.frames == 8

when isMainModule:
  main()
