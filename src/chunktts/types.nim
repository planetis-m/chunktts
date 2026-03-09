import openai/core

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
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    AudioError
