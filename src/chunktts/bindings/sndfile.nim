type
  SfCount* = clonglong
  SndFileHandle* = distinct pointer

  SfVioGetFilelen* = proc(userData: pointer): SfCount {.cdecl.}
  SfVioSeek* = proc(offset: SfCount; whence: cint; userData: pointer): SfCount {.cdecl.}
  SfVioRead* = proc(
    ptrBuffer: pointer;
    count: SfCount;
    userData: pointer
  ): SfCount {.cdecl.}
  SfVioWrite* = proc(
    ptrBuffer: pointer;
    count: SfCount;
    userData: pointer
  ): SfCount {.cdecl.}
  SfVioTell* = proc(userData: pointer): SfCount {.cdecl.}

  SfInfo* {.bycopy, importc: "SF_INFO", header: "<sndfile.h>".} = object
    frames*: SfCount
    samplerate*: cint
    channels*: cint
    format*: cint
    sections*: cint
    seekable*: cint

  SfVirtualIo* {.bycopy, importc: "SF_VIRTUAL_IO", header: "<sndfile.h>".} = object
    get_filelen*: SfVioGetFilelen
    seek*: SfVioSeek
    read*: SfVioRead
    write*: SfVioWrite
    tell*: SfVioTell

const
  SFM_READ* = 0x10
  SFM_WRITE* = 0x20

  SfSeekSet* = 0.cint
  SfSeekCur* = 1.cint
  SfSeekEnd* = 2.cint

  SF_FORMAT_OGG* = 0x200000
  SF_FORMAT_OPUS* = 0x0064

{.push importc, callconv: cdecl, header: "<sndfile.h>".}

proc sf_open*(path: cstring; mode: cint; sfinfo: ptr SfInfo): SndFileHandle
proc sf_open_virtual*(sfvirtual: ptr SfVirtualIo; mode: cint;
    sfinfo: ptr SfInfo; userData: pointer): SndFileHandle
proc sf_close*(sndfile: SndFileHandle): cint
proc sf_strerror*(sndfile: SndFileHandle): cstring
proc sf_error*(sndfile: SndFileHandle): cint
proc sf_readf_float*(sndfile: SndFileHandle; buffer: ptr cfloat; frames: SfCount): SfCount
proc sf_writef_float*(sndfile: SndFileHandle; buffer: ptr cfloat; frames: SfCount): SfCount

{.pop.}
