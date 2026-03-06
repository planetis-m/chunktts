proc runTest(cmd: string) =
  echo "Running: " & cmd
  exec cmd

task test, "Run CI tests":
  runTest "nim c -r tests/test_chunk_split.nim"
  runTest "nim c -r tests/test_request_id_codec.nim"
  runTest "nim c -r tests/test_retry_and_errors.nim"
  runTest "nim c -r tests/test_sndfile_wrap.nim"
  runTest "nim c -r tests/test_openai_audio_speech.nim"
  runTest "nim c -r tests/test_pipeline_integration.nim"
