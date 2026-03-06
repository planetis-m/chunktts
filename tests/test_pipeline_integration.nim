import std/[asyncdispatch, asynchttpserver, base64, locks, os, strutils, times]
import relay
import openai
import chunktts/[pipeline, sndfile_wrap, types]

const
  SampleWavBase64 =
    "UklGRjQAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YRAAAAAAAOgDGPz0AQz+AAAAAAAA"
  SampleWav = decode(SampleWavBase64)

type
  ServerState = object
    lock: Lock
    port: int
    ready: bool
    stopped: bool
    expectedRequests: int
    totalRequests: int
    activeRequests: int
    maxActiveRequests: int
    retryChunkRequests: int
    failure: string

proc markReady(state: ptr ServerState; port: int) =
  acquire(state.lock)
  state.port = port
  state.ready = true
  release(state.lock)

proc markFailure(state: ptr ServerState; message: string) =
  acquire(state.lock)
  if state.failure.len == 0:
    state.failure = message
  release(state.lock)

proc beginRequest(state: ptr ServerState) =
  acquire(state.lock)
  inc state.activeRequests
  if state.activeRequests > state.maxActiveRequests:
    state.maxActiveRequests = state.activeRequests
  release(state.lock)

proc endRequest(state: ptr ServerState) =
  acquire(state.lock)
  dec state.activeRequests
  release(state.lock)

proc noteRetryChunkRequest(state: ptr ServerState): int =
  acquire(state.lock)
  inc state.retryChunkRequests
  result = state.retryChunkRequests
  release(state.lock)

proc noteResponseSent(state: ptr ServerState): bool =
  acquire(state.lock)
  inc state.totalRequests
  result = state.totalRequests >= state.expectedRequests
  if result:
    state.stopped = true
  release(state.lock)

proc snapshot(state: ptr ServerState): tuple[maxActive, retryRequests: int; failure: string] =
  acquire(state.lock)
  result = (
    maxActive: state.maxActiveRequests,
    retryRequests: state.retryChunkRequests,
    failure: state.failure
  )
  release(state.lock)

proc isStopped(state: ptr ServerState): bool =
  acquire(state.lock)
  result = state.stopped
  release(state.lock)

proc serverMain(state: ptr ServerState) {.thread.} =
  proc run() {.async.} =
    var server = newAsyncHttpServer()
    server.listen(Port(0))
    state.markReady(int(server.getPort))

    proc handleRequest(req: Request) {.async, gcsafe.} =
      state.beginRequest()
      defer:
        state.endRequest()

      let headers = newHttpHeaders([("Content-Type", "audio/wav")])
      let isRetryChunk = req.body.contains("\"input\":\"retry me\"")

      if isRetryChunk and state.noteRetryChunkRequest() == 1:
        await sleepAsync(75)
        await req.respond(Http429, "")
      else:
        await sleepAsync(150)
        await req.respond(Http200, SampleWav, headers)

      if state.noteResponseSent():
        server.close()

    while not state.isStopped():
      try:
        if server.shouldAcceptRequest():
          await server.acceptRequest(handleRequest)
        else:
          await sleepAsync(25)
      except CatchableError:
        if not state.isStopped():
          state.markFailure(getCurrentExceptionMsg())
        break

  try:
    waitFor run()
  except CatchableError:
    state.markFailure(getCurrentExceptionMsg())

proc uniqueTempDir(): string =
  result = getTempDir() / ("chunktts-pipeline-" & $getTime().toUnix())
  var suffix = 0
  while dirExists(result):
    inc suffix
    result = getTempDir() / ("chunktts-pipeline-" & $getTime().toUnix() & "-" & $suffix)

proc main() =
  var state = ServerState(expectedRequests: 4)
  initLock(state.lock)
  defer:
    deinitLock(state.lock)

  var thread: Thread[ptr ServerState]
  createThread(thread, serverMain, addr state)

  var port = 0
  while port == 0:
    sleep(10)
    acquire(state.lock)
    if state.ready:
      port = state.port
    release(state.lock)

  let outputDir = uniqueTempDir()
  let outputPath = outputDir / "combined.opus"
  createDir(outputDir)
  defer:
    if fileExists(outputPath):
      removeFile(outputPath)
    if dirExists(outputDir):
      removeDir(outputDir)

  let cfg = RuntimeConfig(
    outputPath: outputPath,
    breakMarker: "<break>",
    openaiConfig: OpenAIConfig(
      url: "http://127.0.0.1:" & $port & "/v1/openai/audio/speech",
      apiKey: "test-key"
    ),
    networkConfig: NetworkConfig(
      model: "hexgrad/Kokoro-82M",
      voice: "af_bella",
      speed: 1.0,
      maxInflight: 2,
      totalTimeoutMs: 30_000,
      maxRetries: 1
    )
  )

  let client = newRelay(
    maxInFlight = cfg.networkConfig.maxInflight,
    defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
  )
  defer:
    client.close()

  let allSucceeded = runPipeline(cfg, @["slow one", "retry me", "slow two"], client)
  joinThread(thread)

  let metrics = snapshot(addr state)
  doAssert metrics.failure.len == 0, metrics.failure
  doAssert allSucceeded
  doAssert metrics.maxActive == 2
  doAssert metrics.retryRequests == 2

  doAssert fileExists(outputPath)
  let info = readAudioFileInfo(outputPath)
  doAssert info.sampleRate == 8000
  doAssert info.channels == 1
  doAssert info.frames == 24

when isMainModule:
  main()
