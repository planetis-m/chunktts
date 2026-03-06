import chunktts/request_id_codec

proc main() =
  ensureRequestIdCapacity(10, 5)

  let packed = packRequestId(7, 3)
  let unpacked = unpackRequestId(packed)
  doAssert unpacked.seqId == 7
  doAssert unpacked.attempt == 3

when isMainModule:
  main()
