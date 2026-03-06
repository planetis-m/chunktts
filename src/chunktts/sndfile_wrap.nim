import ./bindings/sndfile

const SfFormatOpus* = SF_FORMAT_OGG or SF_FORMAT_OPUS

type
  AudioFile* = object
    raw: SndFileHandle
    info: SfInfo

  DecodedAudio* = object
    sampleRate*: int
    channels*: int
    frames*: int64
    samples*: seq[float32]

proc `=destroy`*(audioFile: AudioFile) =
  if pointer(audioFile.raw) != nil:
    discard sf_close(audioFile.raw)

proc `=copy`*(dest: var AudioFile; src: AudioFile) {.error.}
proc `=dup`*(src: AudioFile): AudioFile {.error.}

proc `=sink`*(dest: var AudioFile; src: AudioFile) =
  `=destroy`(dest)
  dest.raw = src.raw
  dest.info = src.info

proc `=wasMoved`*(audioFile: var AudioFile) =
  audioFile.raw = SndFileHandle(nil)
  audioFile.info = default(SfInfo)

proc raiseSndFileError*(context: string; sndFile = SndFileHandle(nil)) {.noinline.} =
  let detail = $sf_strerror(sndFile)
  raise newException(IOError, context & ": " & detail)

proc openAudioFile*(path: string): AudioFile =
  var info: SfInfo
  result = AudioFile(
    raw: sf_open(path.cstring, SFM_READ, addr info),
    info: info
  )
  if pointer(result.raw) == nil:
    raiseSndFileError("sf_open failed")

proc sampleRate*(audioFile: AudioFile): int {.inline.} =
  int(audioFile.info.samplerate)

proc channels*(audioFile: AudioFile): int {.inline.} =
  int(audioFile.info.channels)

proc frames*(audioFile: AudioFile): int64 {.inline.} =
  int64(audioFile.info.frames)

proc openAudioFileForWrite(path: string; sampleRate, channels: int;
    format: cint): AudioFile =
  let rawInfo = SfInfo(
    frames: 0,
    samplerate: sampleRate.cint,
    channels: channels.cint,
    format: format,
    sections: 0,
    seekable: 0
  )
  result = AudioFile(
    raw: sf_open(path.cstring, SFM_WRITE, addr rawInfo),
    info: rawInfo
  )
  if pointer(result.raw) == nil:
    raiseSndFileError("sf_open failed")

proc readDecodedAudio*(path: string): DecodedAudio =
  let audioFile = openAudioFile(path)
  let frames = audioFile.frames
  let channels = audioFile.channels
  let sampleCount = int(frames) * channels
  result = DecodedAudio(
    sampleRate: audioFile.sampleRate,
    channels: channels,
    frames: frames,
    samples: newSeq[float32](sampleCount)
  )

  if sampleCount > 0:
    let framesRead = sf_readf_float(
      audioFile.raw,
      cast[ptr cfloat](addr result.samples[0]),
      frames.SfCount
    )
    if framesRead != frames.SfCount:
      raiseSndFileError("sf_readf_float failed", audioFile.raw)

proc concatAudio*(chunks: openArray[DecodedAudio]): DecodedAudio =
  if chunks.len == 0:
    raise newException(ValueError, "cannot concatenate zero audio chunks")

  let sampleRate = chunks[0].sampleRate
  let channels = chunks[0].channels
  var totalFrames = 0'i64

  for chunk in chunks:
    if chunk.sampleRate != sampleRate:
      raise newException(ValueError, "chunk sample rates do not match")
    if chunk.channels != channels:
      raise newException(ValueError, "chunk channel counts do not match")
    totalFrames.inc(chunk.frames)

  result = DecodedAudio(
    sampleRate: sampleRate,
    channels: channels,
    frames: totalFrames,
    samples: @[]
  )

  for chunk in chunks:
    result.samples.add(chunk.samples)

proc writeOpusFile*(path: string; audio: DecodedAudio) =
  let audioFile = openAudioFileForWrite(
    path,
    audio.sampleRate,
    audio.channels,
    SfFormatOpus
  )

  if audio.samples.len > 0:
    let framesWritten = sf_writef_float(
      audioFile.raw,
      cast[ptr cfloat](addr audio.samples[0]),
      audio.frames.SfCount
    )
    if framesWritten != audio.frames.SfCount:
      raiseSndFileError("sf_writef_float failed", audioFile.raw)
