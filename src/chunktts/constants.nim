const
  DefaultConfigPath* = "config.json"

  ApiUrl* = "https://api.deepinfra.com/v1/openai/audio/speech"
  Model* = "hexgrad/Kokoro-82M"
  BreakMarker* = "<break>"
  Voice* = "af_bella"
  Speed* = 1.0
  MaxInflight* = 32
  TotalTimeoutMs* = 120_000
  MaxRetries* = 5

  ExitAllOk* = 0
  ExitPartialFailure* = 2
  ExitFatalRuntime* = 3
