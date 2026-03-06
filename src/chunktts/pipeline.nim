import std/[monotimes, os, random, strformat, strutils, times]
import relay
import openai
import openai_audio_speech, openai_retry
import ./[constants, request_id_codec, retry_and_errors, retry_queue, sndfile_wrap,
  tts_client, types]

const
  RetryPollSliceMs = 25

type
  PipelineState = object
    inFlightCount: int
    activeCount: int
    staged: seq[ChunkResult]
    retryQueue: RetryQueue
    nextSubmitSeqId: int
    nextFinalizeSeqId: int
    remaining: int
    submitBatch: RequestBatch
    allSucceeded: bool
    rng: Rand

proc okChunkResult(path: sink string; attempts: int;
    audioInfo: ChunkAudioInfo): ChunkResult {.inline.} =
  ChunkResult(
    outputPath: path,
    attempts: attempts,
    status: ChunkOk,
    audioInfo: audioInfo,
    errorKind: NoError,
    errorMessage: "",
    httpStatus: 0
  )

proc errorChunkResult(attempts: int; kind: ChunkErrorKind;
    message: sink string; httpStatus = 0): ChunkResult {.inline.} =
  ChunkResult(
    outputPath: "",
    attempts: attempts,
    status: ChunkError,
    audioInfo: default(ChunkAudioInfo),
    errorKind: kind,
    errorMessage: message,
    httpStatus: httpStatus
  )

proc initPipelineState(total: int): PipelineState =
  PipelineState(
    inFlightCount: 0,
    activeCount: 0,
    staged: newSeq[ChunkResult](total),
    retryQueue: initRetryQueue(),
    nextSubmitSeqId: 0,
    nextFinalizeSeqId: 0,
    remaining: total,
    submitBatch: RequestBatch(),
    allSucceeded: true,
    rng: initRand(getMonoTime().ticks)
  )

proc outputFilePath(cfg: RuntimeConfig; seqId: int): string =
  let fileName = align($(seqId + 1), FileDigits, '0') & ".wav"
  result = cfg.outputDir / fileName

proc tempFilePath(cfg: RuntimeConfig; seqId, attempt: int): string =
  let fileName = fmt".{align($(seqId + 1), FileDigits, '0')}.attempt{attempt}.tmp.wav"
  result = cfg.outputDir / fileName

proc replaceFile(srcPath, dstPath: string) =
  if fileExists(dstPath):
    removeFile(dstPath)
  moveFile(srcPath, dstPath)

proc persistAudioFile(cfg: RuntimeConfig; seqId, attempt: int;
    body: string): tuple[path: string, info: ChunkAudioInfo] =
  let finalPath = outputFilePath(cfg, seqId)
  let tempPath = tempFilePath(cfg, seqId, attempt)
  var finalized = false

  writeFile(tempPath, body)
  defer:
    if not finalized and fileExists(tempPath):
      removeFile(tempPath)

  let fileInfo = readAudioFileInfo(tempPath)
  replaceFile(tempPath, finalPath)
  finalized = true
  result = (
    path: finalPath,
    info: ChunkAudioInfo(
      sampleRate: fileInfo.sampleRate,
      channels: fileInfo.channels,
      frames: fileInfo.frames
    )
  )

proc flushOrderedResults(state: var PipelineState) =
  while state.nextFinalizeSeqId < state.staged.len and
      state.staged[state.nextFinalizeSeqId].status != ChunkPending:
    if state.staged[state.nextFinalizeSeqId].status != ChunkOk:
      state.allSucceeded = false
    state.staged[state.nextFinalizeSeqId] = default(ChunkResult)
    inc state.nextFinalizeSeqId
    dec state.remaining

proc startBatchIfAny(client: Relay; state: var PipelineState) =
  if state.submitBatch.len > 0:
    client.startRequests(state.submitBatch)

proc queueAttempt(cfg: RuntimeConfig; chunks: seq[string]; seqId, attempt: int;
    state: var PipelineState): bool =
  let requestId = packRequestId(seqId, attempt)

  try:
    speechAdd(
      state.submitBatch,
      cfg.openaiConfig,
      params = buildSpeechParams(cfg, chunks[seqId]),
      requestId = requestId,
      timeoutMs = cfg.networkConfig.totalTimeoutMs
    )
    inc state.inFlightCount
    result = true
  except CatchableError:
    state.staged[seqId] = errorChunkResult(
      attempts = attempt,
      kind = NetworkError,
      message = getCurrentExceptionMsg()
    )

proc submitDueRetries(cfg: RuntimeConfig; chunks: seq[string]; maxInFlight: int;
    state: var PipelineState) =
  if state.inFlightCount < maxInFlight:
    let now = getMonoTime()
    var retryItem: RetryItem
    while state.inFlightCount < maxInFlight and
        popDueRetry(state.retryQueue, now, retryItem):
      if not queueAttempt(cfg, chunks, retryItem.seqId, retryItem.attempt, state):
        dec state.activeCount

proc submitFreshAttempts(cfg: RuntimeConfig; chunks: seq[string]; maxInFlight: int;
    state: var PipelineState) =
  if state.activeCount < maxInFlight and state.nextSubmitSeqId < chunks.len:
    let capacity = maxInFlight - state.activeCount
    var added = 0
    while added < capacity and state.nextSubmitSeqId < chunks.len:
      inc state.activeCount
      if queueAttempt(cfg, chunks, state.nextSubmitSeqId, 1, state):
        inc added
      else:
        dec state.activeCount
      inc state.nextSubmitSeqId

proc processAudioSuccess(cfg: RuntimeConfig; seqId, attempt: int; body: string;
    state: var PipelineState) =
  if body.len == 0:
    state.staged[seqId] = errorChunkResult(
      attempts = attempt,
      kind = AudioError,
      message = "tts response body was empty"
    )
  else:
    try:
      let persisted = persistAudioFile(cfg, seqId, attempt, body)
      state.staged[seqId] = okChunkResult(
        path = persisted.path,
        attempts = attempt,
        audioInfo = persisted.info
      )
    except IOError:
      state.staged[seqId] = errorChunkResult(
        attempts = attempt,
        kind = AudioError,
        message = getCurrentExceptionMsg()
      )
    except OSError:
      state.staged[seqId] = errorChunkResult(
        attempts = attempt,
        kind = FileError,
        message = getCurrentExceptionMsg()
      )

proc processResult(cfg: RuntimeConfig; item: RequestResult; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  let requestId = item.response.request.requestId
  let meta = unpackRequestId(requestId)
  let seqId = meta.seqId
  let attempt = meta.attempt
  dec state.inFlightCount

  if shouldRetry(item, attempt, maxAttempts):
    let delayMs = retryDelayMs(state.rng, attempt, retryPolicy)
    state.retryQueue.addRetry(RetryItem(
      seqId: seqId,
      attempt: attempt + 1,
      dueAt: getMonoTime() + initDuration(milliseconds = delayMs)
    ))
  else:
    if item.error.kind != teNone or not isHttpSuccess(item.response.code):
      let finalError = classifyFinalError(item)
      state.staged[seqId] = errorChunkResult(
        attempts = attempt,
        kind = finalError.kind,
        message = finalError.message,
        httpStatus = finalError.httpStatus
      )
    else:
      processAudioSuccess(cfg, seqId, attempt, item.response.body, state)
    dec state.activeCount

proc drainReadyResults(cfg: RuntimeConfig; client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState): bool =
  result = false
  var item: RequestResult
  while client.pollForResult(item):
    processResult(cfg, item, maxAttempts, retryPolicy, state)
    result = true

proc waitForSingleResult(cfg: RuntimeConfig; client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  var item: RequestResult
  if not client.waitForResult(item):
    raise newException(IOError, "relay worker stopped before all results arrived")
  processResult(cfg, item, maxAttempts, retryPolicy, state)

proc waitForProgress(cfg: RuntimeConfig; client: Relay; maxInFlight, maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState) =
  if state.inFlightCount == 0:
    let sleepMs = nextRetryDelayMs(state.retryQueue)
    if sleepMs < 0:
      raise newException(ValueError, "pipeline stalled before all results arrived")
    if sleepMs > 0:
      sleep(sleepMs)
  else:
    let nextRetryMs = nextRetryDelayMs(state.retryQueue)
    if nextRetryMs < 0:
      waitForSingleResult(cfg, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs == 0 and state.inFlightCount == maxInFlight:
      waitForSingleResult(cfg, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs > 0:
      sleep(min(RetryPollSliceMs, nextRetryMs))

proc runPipeline*(cfg: RuntimeConfig; chunks: seq[string]; client: Relay): bool =
  let total = chunks.len
  let maxInFlight = max(1, cfg.networkConfig.maxInflight)
  let maxAttempts = max(1, cfg.networkConfig.maxRetries + 1)
  let retryPolicy = defaultRetryPolicy(maxAttempts = maxAttempts)
  ensureRequestIdCapacity(total, maxAttempts)

  var state = initPipelineState(total)

  while state.remaining > 0:
    submitDueRetries(cfg, chunks, maxInFlight, state)
    submitFreshAttempts(cfg, chunks, maxInFlight, state)
    startBatchIfAny(client, state)
    flushOrderedResults(state)

    let drained = drainReadyResults(cfg, client, maxAttempts, retryPolicy, state)
    flushOrderedResults(state)

    if state.remaining > 0 and not drained:
      waitForProgress(cfg, client, maxInFlight, maxAttempts, retryPolicy, state)
      flushOrderedResults(state)

  result = state.allSucceeded
