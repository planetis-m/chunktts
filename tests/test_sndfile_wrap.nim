import std/[base64, os]
import chunktts/sndfile_wrap

const SampleWavBase64 =
  "UklGRjQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YRAAAAAAAOgDGPz0AQz+AAAAAAAA"

proc main() =
  let tempDir = getTempDir() / "chunktts-sndfile-test"
  let wavPath = tempDir / "input.wav"
  let opusPath = tempDir / "output.opus"
  createDir(tempDir)
  defer:
    if fileExists(wavPath):
      removeFile(wavPath)
    if fileExists(opusPath):
      removeFile(opusPath)
    if dirExists(tempDir):
      removeDir(tempDir)

  writeFile(wavPath, decode(SampleWavBase64))

  let decoded = readDecodedAudio(wavPath)
  doAssert decoded.sampleRate == 8000
  doAssert decoded.channels == 1
  doAssert decoded.frames == 8

  writeOpusFile(opusPath, decoded)

  let opusAudio = openAudioFile(opusPath)
  doAssert opusAudio.sampleRate == 8000
  doAssert opusAudio.channels == 1
  doAssert opusAudio.frames == 8

when isMainModule:
  main()
