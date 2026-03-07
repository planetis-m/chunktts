import openai/audio_speech
import ./types

proc buildSpeechParams*(cfg: RuntimeConfig; text: sink string): AudioSpeechCreateParams =
  speechCreate(
    model = cfg.networkConfig.model,
    input = text,
    voice = cfg.networkConfig.voice,
    responseFormat = AudioSpeechResponseFormat.wav,
    speed = cfg.networkConfig.speed
  )
