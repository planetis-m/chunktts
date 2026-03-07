import std/[envvars, parseopt, paths, files]
from std/os import getAppDir
import jsonx
import openai/core
import ./[constants, logging, types]

{.define: jsonxLenient.}

type
  CliArgs = object
    inputPath: string
    outputPath: string

  JsonRuntimeConfig = object
    api_key: string
    api_url: string
    model: string
    voice: string
    speed: float
    max_inflight: int
    max_retries: int

const HelpText = """
Usage:
  chunktts INPUT.txt OUTPUT.opus

Options:
  --help, -h       Show this help and exit.
"""

proc cliError(message: string) =
  quit(message & "\n\n" & HelpText, ExitFatalRuntime)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(inputPath: "", outputPath: "")
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len == 0:
        result.inputPath = parser.key
      elif result.outputPath.len == 0:
        result.outputPath = parser.key
      else:
        cliError("too many positional arguments")
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

  if result.inputPath.len == 0:
    cliError("missing required INPUT.txt argument")
  if result.outputPath.len == 0:
    cliError("missing required OUTPUT.opus argument")

proc defaultJsonRuntimeConfig(): JsonRuntimeConfig =
  JsonRuntimeConfig(
    api_key: "",
    api_url: ApiUrl,
    model: Model,
    voice: Voice,
    speed: Speed,
    max_inflight: MaxInflight,
    max_retries: MaxRetries
  )

proc loadOptionalJsonRuntimeConfig(path: Path): JsonRuntimeConfig =
  result = defaultJsonRuntimeConfig()
  if fileExists(path):
    try:
      jsonx.fromFile(path, result)
      logInfo("loaded config from " & $path)
    except CatchableError:
      logWarn("failed to parse config file at " & $path &
        "; using built-in defaults")
  else:
    logInfo("config file not found at " & $path & "; using built-in defaults")

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

template ifNonNegative(value, fallback: untyped): untyped =
  if value >= 0: value
  else: fallback

template ifInRange(value, minValue, maxValue, fallback: untyped): untyped =
  if value >= minValue and value <= maxValue: value
  else: fallback

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let configPath = Path(getAppDir()) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)
  let resolvedApiKey = resolveApiKey(rawConfig.api_key)
  let resolvedApiUrl = ifNonEmpty(rawConfig.api_url, ApiUrl)

  result = RuntimeConfig(
    inputPath: parsed.inputPath,
    outputPath: parsed.outputPath,
    breakMarker: BreakMarker,
    openaiConfig: OpenAIConfig(
      url: resolvedApiUrl,
      apiKey: resolvedApiKey
    ),
    networkConfig: NetworkConfig(
      model: ifNonEmpty(rawConfig.model, Model),
      voice: ifNonEmpty(rawConfig.voice, Voice),
      speed: ifInRange(rawConfig.speed, 0.25, 4.0, Speed),
      maxInflight: ifPositive(rawConfig.max_inflight, MaxInflight),
      totalTimeoutMs: TotalTimeoutMs,
      maxRetries: ifNonNegative(rawConfig.max_retries, MaxRetries)
    )
  )
