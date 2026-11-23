This C consumer checks the actual full embedding library's ReleaseSafe/version metadata, runtime initialization and configuration allocation/lifecycle. Build a managed OpenGL/CoreText ReleaseSafe library with version 1.3.0, then compile:

```sh
clang -Iinclude build_support/reference_probes/library_info/main.c -L.witty-build/artifacts -lwitty -Wl,-rpath,"$PWD/.witty-build/artifacts" -o /tmp/library-info-consumer
/tmp/library-info-consumer --font-size=17
```

Darwin intentionally reads CLI configuration from NSProcessInfo.arguments, as in the original. Invoke the consumer with `--font-size=17` for that assertion.

The initial native run exposed V's compiler-owned opaque `os.execute` mutex buffer's alignment-1 declaration. The build driver copies that selected runtime module and changes only its 128-byte storage to 16 u64 words, preserving the operations and capacity while providing native mutex alignment. It does not modify the installed compiler. The full managed native link also needs the unchanged Fontconfig/HarfBuzz packages retained by V's runtime backend dispatch, even with CoreText selected.
