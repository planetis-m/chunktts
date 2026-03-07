import ./bindings/sndfile

type
  AudioFile* = object
    raw: SndFileHandle
    info: SfInfo

  DecodedAudio* = object
    sampleRate*: int
    channels*: int
    frames*: int64
    samples*: seq[float32]

  MemoryAudioReader = object
    encoded: string
    position: int64

proc memoryReader(userData: pointer): ptr MemoryAudioReader {.inline.} =
  cast[ptr MemoryAudioReader](userData)

proc memoryGetFileLen(userData: pointer): SfCount {.cdecl.} =
  result = SfCount(memoryReader(userData).encoded.len)

proc memorySeek(offset: SfCount; whence: cint; userData: pointer): SfCount {.cdecl.} =
  let reader = memoryReader(userData)
  let encodedLen = int64(reader.encoded.len)
  var nextPosition: int64
  var hasValidWhence = true

  case whence
  of SfSeekSet:
    nextPosition = int64(offset)
  of SfSeekCur:
    nextPosition = reader.position + int64(offset)
  of SfSeekEnd:
    nextPosition = encodedLen + int64(offset)
  else:
    hasValidWhence = false

  if not hasValidWhence:
    result = -1
  elif nextPosition < 0 or nextPosition > encodedLen:
    result = -1
  else:
    reader.position = nextPosition
    result = SfCount(nextPosition)

proc memoryRead(ptrBuffer: pointer; count: SfCount; userData: pointer): SfCount {.cdecl.} =
  let reader = memoryReader(userData)
  if count > 0:
    let remaining = int64(reader.encoded.len) - reader.position
    if remaining > 0:
      let readLen = min(int64(count), remaining)
      copyMem(ptrBuffer, addr reader.encoded[int(reader.position)], int(readLen))
      reader.position.inc(readLen)
      result = SfCount(readLen)

proc memoryTell(userData: pointer): SfCount {.cdecl.} =
  result = SfCount(memoryReader(userData).position)

let MemoryReadVirtualIo = SfVirtualIo(
  get_filelen: memoryGetFileLen,
  seek: memorySeek,
  read: memoryRead,
  write: nil,
  tell: memoryTell
)

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

proc openMemoryAudioFile(reader: var MemoryAudioReader): AudioFile =
  var info: SfInfo
  result = AudioFile(
    raw: sf_open_virtual(
      addr MemoryReadVirtualIo,
      SFM_READ,
      addr info,
      cast[pointer](addr reader)
    ),
    info: info
  )
  if pointer(result.raw) == nil:
    raiseSndFileError("sf_open_virtual failed")

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

proc decodeAudioFile(audioFile: sink AudioFile): DecodedAudio =
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

proc readDecodedAudio*(path: string): DecodedAudio =
  result = decodeAudioFile(openAudioFile(path))

proc readDecodedAudioBytes*(encoded: sink string): DecodedAudio =
  var reader = MemoryAudioReader(
    encoded: encoded,
    position: 0
  )
  result = decodeAudioFile(openMemoryAudioFile(reader))

proc writeDecodedAudio(audioFile: AudioFile; audio: DecodedAudio) =
  if audio.samples.len > 0:
    let framesWritten = sf_writef_float(
      audioFile.raw,
      cast[ptr cfloat](addr audio.samples[0]),
      audio.frames.SfCount
    )
    if framesWritten != audio.frames.SfCount:
      raiseSndFileError("sf_writef_float failed", audioFile.raw)

proc writeOpusFile*(path: string; audio: DecodedAudio) =
  let audioFile = openAudioFileForWrite(
    path,
    audio.sampleRate,
    audio.channels,
    SF_FORMAT_OGG or SF_FORMAT_OPUS
  )
  writeDecodedAudio(audioFile, audio)

proc writeOpusFile*(path: string; chunks: openArray[DecodedAudio]) =
  if chunks.len == 0:
    raise newException(ValueError, "cannot write zero audio chunks")

  let sampleRate = chunks[0].sampleRate
  let channels = chunks[0].channels
  let audioFile = openAudioFileForWrite(
    path,
    sampleRate,
    channels,
    SF_FORMAT_OGG or SF_FORMAT_OPUS
  )

  for chunk in chunks:
    if chunk.sampleRate != sampleRate:
      raise newException(ValueError, "chunk sample rates do not match")
    if chunk.channels != channels:
      raise newException(ValueError, "chunk channel counts do not match")
    writeDecodedAudio(audioFile, chunk)
