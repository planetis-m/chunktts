import std/[monotimes, os, random, times]
import relay
import openai/[audio_speech, core, retry]
import ./[request_id_codec, retry_and_errors, retry_queue, sndfile_wrap,
  tts_client, types]

const
  RetryPollSliceMs = 25

type
  PipelineState = object
    inFlightCount: int
    activeCount: int
    decodedChunks: seq[DecodedAudio]
    retryQueue: RetryQueue
    nextSubmitSeqId: int
    remaining: int
    submitBatch: RequestBatch
    allSucceeded: bool
    rng: Rand

proc initPipelineState(total: int): PipelineState =
  PipelineState(
    inFlightCount: 0,
    activeCount: 0,
    decodedChunks: newSeq[DecodedAudio](total),
    retryQueue: initRetryQueue(),
    nextSubmitSeqId: 0,
    remaining: total,
    submitBatch: RequestBatch(),
    allSucceeded: true,
    rng: initRand(getMonoTime().ticks)
  )

proc finalizeChunk(state: var PipelineState; succeeded: bool) =
  if not succeeded:
    state.allSucceeded = false
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
    state.finalizeChunk(succeeded = false)

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

proc processAudioSuccess(seqId: int; body: string; state: var PipelineState) =
  if body.len == 0:
    state.finalizeChunk(succeeded = false)
  else:
    try:
      let audio = readDecodedAudioBytes(body)
      state.decodedChunks[seqId] = audio
      state.finalizeChunk(succeeded = true)
    except CatchableError:
      state.finalizeChunk(succeeded = false)

proc processResult(item: RequestResult; maxAttempts: int; retryPolicy: RetryPolicy;
    state: var PipelineState) =
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
      state.finalizeChunk(succeeded = false)
    else:
      processAudioSuccess(seqId, item.response.body, state)
    dec state.activeCount

proc drainReadyResults(client: Relay; maxAttempts: int;
    retryPolicy: RetryPolicy; state: var PipelineState): bool =
  result = false
  var item: RequestResult
  while client.pollForResult(item):
    processResult(item, maxAttempts, retryPolicy, state)
    result = true

proc waitForSingleResult(client: Relay; maxAttempts: int; retryPolicy: RetryPolicy;
    state: var PipelineState) =
  var item: RequestResult
  if not client.waitForResult(item):
    raise newException(IOError, "relay worker stopped before all results arrived")
  processResult(item, maxAttempts, retryPolicy, state)

proc waitForProgress(client: Relay; maxInFlight, maxAttempts: int;
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
      waitForSingleResult(client, maxAttempts, retryPolicy, state)
    elif nextRetryMs == 0 and state.inFlightCount == maxInFlight:
      waitForSingleResult(client, maxAttempts, retryPolicy, state)
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
    let drained = drainReadyResults(client, maxAttempts, retryPolicy, state)

    if state.remaining > 0 and not drained:
      waitForProgress(client, maxInFlight, maxAttempts, retryPolicy, state)

  if state.allSucceeded:
    writeOpusFile(cfg.outputPath, state.decodedChunks)

  result = state.allSucceeded
