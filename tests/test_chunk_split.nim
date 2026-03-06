import chunktts/chunk_split

proc main() =
  doAssert splitChunks("alpha<break>beta", "<break>") == @["alpha", "beta"]
  doAssert splitChunks(" alpha <break>  beta  ", "<break>") == @["alpha", "beta"]
  doAssert splitChunks("alpha<break><break>beta", "<break>") == @["alpha", "beta"]
  doAssert splitChunks("standalone text", "<break>") == @["standalone text"]
  doAssert splitChunks("one||two", "||") == @["one", "two"]

when isMainModule:
  main()
