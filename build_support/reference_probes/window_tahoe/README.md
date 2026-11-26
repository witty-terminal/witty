`run.py` compiles the unchanged `TitlebarTabsTahoeTerminalWindow.swift` and its
unchanged view/window traversal helpers. A small native NSWindow base fixture
supplies the inherited font/config/accessory boundary. The probe compares the
source view model and real toolbar item contract with the translated AppKit
consumer's JSON from `macos/window_tahoe_darwin_test.v`.

```sh
VEXE=/path/to/v WITTY_TAHOE_MODEL_OUTPUT=/tmp/witty-tahoe-model.json \
  /path/to/v -path "$PWD|@vlib|@vmodules" run tools/build test \
  -Dtest-filter=tahoe -Dsentry=false -Drenderer=opengl
python3 build_support/reference_probes/window_tahoe/run.py \
  /path/to/ghostty /tmp/witty-tahoe-model.json
```

The ten records cover asynchronous title/font publication, empty-title spacing,
main-window state, the tab placeholder, toolbar identifiers, priority, border
and compression resistance. Witty renders `TitleItem` with Core Text shaping
and GG Canvas storage in an AppKit view. The title view uses the source
one-by-one intrinsic size while tabs are shown. The comparison covers the model
and toolbar API behavior.
The native test also exercises independent repeated title-item creation, real
tab constraints with visible and hidden window buttons, frame notification
reset, inherited tab-group KVO, transparent/glass titlebar coloring, update-pill
placement without a titlebar accessory, and the native new-tab button's focused
surface binding. After a titlebar-style hot reload, it removes and readds the
real native tab accessory and observes `.right` layout at entry to AppKit's
superclass method. Its click test
supplies native Objective-C event fixtures and intercepts fallback dispatch;
it does not perform an interactive context-menu session or fullscreen transition.
