# Issues I found during development

I got a segfault and took help by a genie to gather the below, will create an issue to koka lang later


## Segfault in `kk_cctx_copy` under `-O1`/`-O2` with stacked effect handlers

### Summary

A program that stacks two custom effect handlers (`exit` control effect + `bio` fun effect) and uses `foreach-indexed` with a `var` inside the handler body segfaults when compiled with `-O1` or `-O2`, but works correctly with debug (no optimization flag).

### Environment

- **Koka**: 3.2.3 (ghc release version, Mar 18 2026)
- **OS**: macOS Darwin 23.5.0 arm64
- **Compiler**: Apple clang 16.0.0

### Reproducer

Full repository: https://github.com/cladam/koka-labs

```bash
git clone https://github.com/cladam/koka-labs.git
cd koka-labs
koka src/ls.kk -o ls-debug     # works
koka -O2 src/ls.kk -o ls-opt   # builds, segfaults at runtime
chmod +x ls-opt && ./ls-opt    # segfault
```

The key pattern in the code is:

```koka
effect exit
  ctl exit( exitcode : int ) : a

fun status( action : () -> <exit|e> a ) : e int
  with final ctl exit(code) code
  action()
  0

effect bio
  fun write( fd : int, s : string ) : ()

fun main()
  val code = status                           // exit effect handler
    with fun write(fd, s) print(s)            // bio effect handler
    var exit-code := 0
    // ... arg parsing ...
    sorted-dirs.foreach-indexed fn(i, dir-path)
      // ... calls echoln (uses bio effect) ...
      val dir-code = list-dir(dir-path, opts, show-header)
      if dir-code > exit-code then exit-code := dir-code
    if exit-code > 0 then exit(exit-code)
  process-exit(code)  // C FFI: exit()
```

A trivial program with the same effect stack does **not** crash — the issue likely requires sufficient code complexity (multiple modules, C FFI extern imports for `stat`/`lstat`, column rendering, etc.) to trigger the CCTX optimization path.

### Backtrace (lldb)

```
* thread #1, queue = 'com.apple.main-thread', stop reason = EXC_BAD_ACCESS (code=1, address=0x20003)
  * frame #0: koka-ls`kk_cctx_copy [inlined] kk_block_field_idx(b=0x0000000000020002) at kklib.h:336:20 [opt]
    frame #1: koka-ls`kk_cctx_copy(res=..., holeptr=0x..., newholeptr=0x..., ctx=0x...) at refcount.c:795:30 [opt]
    frame #2: koka-ls`kk_cctx_copy_apply(res=<unavailable>, ...) at refcount.c:816:19 [opt]
    frame #3: koka-ls`kk_src_ls__lift_main_10762 + 1036
    frame #4: koka-ls`kk_src_ls__lift_main_10762 + 960
    frame #5: koka-ls`kk_src_ls__mlift_main_11169 + 180
    frame #6: koka-ls`kk_src_ls__mlift_main_11170 + 172
    frame #7: koka-ls`kk_src_ls_main_fun3795 + 2292
    frame #8: koka-ls`kk_std_core_hnd__hhandle(...) at std_core_hnd.c:973:22 [opt]
    frame #9: koka-ls`kk_src_ls_main_fun3786 + 236
    frame #10: koka-ls`kk_std_core_hnd__hhandle(...) at std_core_hnd.c:973:22 [opt]
    frame #11: koka-ls`kk_src_ls_main + 236
```

The crash is in `kk_cctx_copy` (refcount.c:795) trying to dereference `0x20003` as a `kk_block_t*`. This appears to be a bogus pointer from a corrupted constructor context during effect handler dispatch.

### Observations

- `-O0` (debug): works perfectly
- `-O1`: segfaults
- `-O2`: segfaults
- A minimal reproducer with the same effect stack pattern does **not** crash — the real program's complexity (C FFI externs, multiple modules, column rendering) seems necessary to trigger it
- The crash occurs in the `foreach-indexed` loop inside the stacked `status`+`bio` handler
