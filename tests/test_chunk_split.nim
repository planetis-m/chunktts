import chunktts/chunk_split

proc main() =
  doAssert splitChunks("alpha<bk>beta", "<bk>") == @["alpha", "beta"]
  doAssert splitChunks(" alpha <bk>  beta  ", "<bk>") == @["alpha", "beta"]
  doAssert splitChunks("alpha<bk><bk>beta", "<bk>") == @["alpha", "beta"]
  doAssert splitChunks("standalone text", "<bk>") == @["standalone text"]
  doAssert splitChunks("one||two", "||") == @["one", "two"]

when isMainModule:
  main()
