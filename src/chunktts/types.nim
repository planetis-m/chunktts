import openai

type
  NetworkConfig* = object
    model*: string
    voice*: string
    speed*: float
    maxInflight*: int
    totalTimeoutMs*: int
    maxRetries*: int

  RuntimeConfig* = object
    inputPath*: string
    outputPath*: string
    breakMarker*: string
    openaiConfig*: OpenAIConfig
    networkConfig*: NetworkConfig

  ChunkErrorKind* = enum
    NoError,
    FileError,
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    AudioError

  ChunkResultStatus* = enum
    ChunkPending = "pending",
    ChunkOk = "ok",
    ChunkError = "error"

  ChunkAudioInfo* = object
    sampleRate*: int
    channels*: int
    frames*: int64

  ChunkResult* = object
    attempts*: int
    status*: ChunkResultStatus
    audioInfo*: ChunkAudioInfo
    errorKind*: ChunkErrorKind
    errorMessage*: string
    httpStatus*: int
