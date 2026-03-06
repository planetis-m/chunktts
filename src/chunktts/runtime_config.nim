import std/[envvars, parseopt, paths, files]
from std/os import getAppDir
import jsonx
import openai
import ./[constants, logging, types]

{.define: jsonxLenient.}

type
  CliArgs = object
    outputPath: string

  JsonRuntimeConfig = object
    api_key: string
    break_marker: string
    voice: string
    speed: float
    max_inflight: int

const HelpText = """
Usage:
  chunktts OUTPUT.opus < input.txt

Options:
  --help, -h       Show this help and exit.
"""

proc cliError(message: string) =
  quit(message & "\n\n" & HelpText, ExitFatalRuntime)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(outputPath: "")
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.outputPath.len == 0:
        result.outputPath = parser.key
      else:
        cliError("multiple output paths specified")
    of cmdLongOption:
      case key
      of "help":
        quit(HelpText, ExitAllOk)
      else:
        cliError("unknown option: --" & key)
    of cmdShortOption:
      if key == "h":
        quit(HelpText, ExitAllOk)
      else:
        cliError("unknown option: -" & key)
    of cmdEnd:
      discard

  if result.outputPath.len == 0:
    cliError("missing required OUTPUT.opus argument")

proc defaultJsonRuntimeConfig(): JsonRuntimeConfig =
  JsonRuntimeConfig(
    api_key: "",
    break_marker: BreakMarker,
    voice: Voice,
    speed: Speed,
    max_inflight: MaxInflight
  )

proc loadOptionalJsonRuntimeConfig(path: Path): JsonRuntimeConfig =
  result = defaultJsonRuntimeConfig()
  if fileExists(path):
    try:
      jsonx.fromFile(path, result)
      logInfo("loaded config from " & $absolutePath(path))
    except CatchableError:
      logWarn("failed to parse config file at " & $absolutePath(path) &
        "; using built-in defaults")
  else:
    logInfo("config file not found at " & $absolutePath(path) & "; using built-in defaults")

proc resolveApiKey(configApiKey: string): string =
  let envApiKey = getEnv("DEEPINFRA_API_KEY")
  if envApiKey.len > 0:
    result = envApiKey
  else:
    result = configApiKey

template ifNonEmpty(value, fallback: untyped): untyped =
  if value.len > 0: value
  else: fallback

template ifPositive(value, fallback: untyped): untyped =
  if value > 0: value
  else: fallback

template ifInRange(value, minValue, maxValue, fallback: untyped): untyped =
  if value >= minValue and value <= maxValue: value
  else: fallback

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let configPath = Path(getAppDir()) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)
  let resolvedApiKey = resolveApiKey(rawConfig.api_key)
  let resolvedBreakMarker = ifNonEmpty(rawConfig.break_marker, BreakMarker)

  if resolvedBreakMarker.len == 0:
    raise newException(ValueError, "break marker must not be empty")

  result = RuntimeConfig(
    outputPath: parsed.outputPath,
    breakMarker: resolvedBreakMarker,
    openaiConfig: OpenAIConfig(
      url: ApiUrl,
      apiKey: resolvedApiKey
    ),
    networkConfig: NetworkConfig(
      model: Model,
      voice: ifNonEmpty(rawConfig.voice, Voice),
      speed: ifInRange(rawConfig.speed, 0.25, 4.0, Speed),
      maxInflight: ifPositive(rawConfig.max_inflight, MaxInflight),
      totalTimeoutMs: TotalTimeoutMs,
      maxRetries: MaxRetries
    )
  )
