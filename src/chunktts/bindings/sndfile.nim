type
  SfCount* = clonglong

  SndFileHandle* = distinct pointer

  SfInfo* {.bycopy, importc: "SF_INFO", header: "<sndfile.h>".} = object
    frames*: SfCount
    samplerate*: cint
    channels*: cint
    format*: cint
    sections*: cint
    seekable*: cint

const
  SFM_READ* = 0x10
  SFM_WRITE* = 0x20

  SF_FORMAT_OGG* = 0x200000
  SF_FORMAT_OPUS* = 0x0064

{.push importc, callconv: cdecl, header: "<sndfile.h>".}

proc sf_open*(path: cstring; mode: cint; sfinfo: ptr SfInfo): SndFileHandle
proc sf_close*(sndfile: SndFileHandle): cint
proc sf_strerror*(sndfile: SndFileHandle): cstring
proc sf_error*(sndfile: SndFileHandle): cint
proc sf_readf_float*(sndfile: SndFileHandle; buffer: ptr cfloat; frames: SfCount): SfCount
proc sf_writef_float*(sndfile: SndFileHandle; buffer: ptr cfloat; frames: SfCount): SfCount

{.pop.}
