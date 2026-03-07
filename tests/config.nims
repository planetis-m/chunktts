switch("path", "$projectdir/../src")
switch("mm", "atomicArc")
switch("passC", "-DCURL_DISABLE_TYPECHECK")

when not defined(windows):
  switch("passL", "-lcurl")
  switch("passL", "-lsndfile")

when defined(windows):
  switch("cc", "vcc")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg/installed/x64-windows-release")
  switch("passC", "-I" & vcpkgRoot & "/include")
  switch("passL", vcpkgRoot & "/lib/libcurl.lib")
  switch("passL", vcpkgRoot & "/lib/sndfile.lib")
elif defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passC", "-I" & staticExec("brew --prefix libsndfile") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
  switch("passL", "-L" & staticExec("brew --prefix libsndfile") & "/lib")

when defined(addressSanitizer):
  switch("debugger", "native")
  switch("define", "noSignalHandler")

  when defined(windows):
    switch("passC", "/fsanitize=address")
  else:
    switch("cc", "clang")
    switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
    switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
