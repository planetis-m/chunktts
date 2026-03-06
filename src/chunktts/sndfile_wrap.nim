import ./bindings/sndfile

type
  AudioFile* = object
    raw: SndFileHandle
    info: SfInfo

  AudioFileInfo* = object
    sampleRate*: int
    channels*: int
    frames*: int64

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

proc infoOf*(audioFile: AudioFile): AudioFileInfo =
  AudioFileInfo(
    sampleRate: int(audioFile.info.samplerate),
    channels: int(audioFile.info.channels),
    frames: int64(audioFile.info.frames)
  )

proc readAudioFileInfo*(path: string): AudioFileInfo =
  let audioFile = openAudioFile(path)
  result = infoOf(audioFile)
