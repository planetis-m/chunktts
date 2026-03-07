import relay
import jsonx
import openai/[audio_speech, core]

proc sampleConfig(apiKey = "sk-test"): OpenAIConfig =
  OpenAIConfig(
    url: "https://api.deepinfra.com/v1/openai/audio/speech",
    apiKey: apiKey
  )

proc main() =
  let params = speechCreate(
    model = "hexgrad/Kokoro-82M",
    input = "hello",
    voice = "af_bella"
  )
  doAssert params.response_format == AudioSpeechResponseFormat.wav
  doAssert params.speed == 1.0

  let cfg = sampleConfig(apiKey = "new-token")
  let req = speechRequest(
    cfg,
    speechCreate(
      model = "hexgrad/Kokoro-82M",
      input = "chunk text",
      voice = "af_bella",
      responseFormat = AudioSpeechResponseFormat.mp3,
      speed = 1.25
    ),
    requestId = 42,
    timeoutMs = 7_000
  )

  doAssert req.verb == hvPost
  doAssert req.url == cfg.url
  doAssert req.headers["Authorization"] == "Bearer new-token"

  let payload = fromJson(req.body, AudioSpeechCreateParams)
  doAssert payload.response_format == AudioSpeechResponseFormat.mp3
  doAssert payload.speed == 1.25

when isMainModule:
  main()
