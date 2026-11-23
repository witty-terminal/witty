// Translated from Ghostty's lib_vt.zig
//
// This is the public API of the witty-vt module.
//
// WARNING: The API is not guaranteed to be stable.
//
// The functionality is extremely stable, since it is extracted
// directly from Ghostty which has been used in real world scenarios
// by thousands of users for years. However, the API itself (functions,
// types, etc.) may change without warning. We're working on stabilizing
// this in the future.

module main

// The public API below reproduces a lot of terminal/main.v but
// is separate because (1) we need our root file to be in `src/`
// so we can access other directories and (2) we may want to withhold
// parts of `terminal` that are not ready for public consumption
// or are too Ghostty-internal.

import terminal
import input

// Re-export key terminal types.
// In Zig these are pub const aliases; in V we use type aliases where
// possible and wrapper functions where needed. The terminal aliases carry a
// `Vt` prefix because unprefixed main-module names (`Parser`, `Point`, ...)
// shadow same-named types in other modules on newer V compilers.

// Core terminal types
pub type VtTerminal = terminal.Terminal

pub type VtScreen = terminal.Screen

pub type VtSelection = terminal.Selection

pub type VtRenderState = terminal.RenderState

// Page types
pub type VtPage = terminal.Page

pub type VtPageList = terminal.PageList

// Cell and style types
pub type VtCellData = terminal.CellData

pub type VtCell = terminal.Cell

pub type VtCharset = terminal.Charset

pub type VtCharsetSlot = terminal.CharsetSlot

pub type VtCharsetActiveSlot = terminal.CharsetActiveSlot

pub type VtCoordinate = terminal.Coordinate

pub type VtCSI = terminal.CSI

pub type VtDCS = terminal.DCS

pub type VtParser = terminal.Parser

pub type VtPin = terminal.Pin

pub type VtPoint = terminal.Point

pub type VtScreenSet = terminal.ScreenSet

pub type VtSizeReportStyle = terminal.SizeReportStyle

pub type VtStringMap = terminal.StringMap

pub type VtStyle = terminal.Style

// `Stream` is the generic `terminal.Stream[H]`. V does not implement generic
// type aliases, so consumers name `terminal.Stream[H]` directly.

pub type VtStreamAction = terminal.StreamAction

pub type VtCursor = terminal.Cursor

pub type VtCursorStyle = terminal.CursorStyle

pub type VtCursorStyleReq = terminal.CursorStyleReq

pub type VtDeviceAttributeReq = terminal.DeviceAttributeReq

pub type VtMode = terminal.Mode

pub type VtModePacked = terminal.ModePacked

pub type VtModifyKeyFormat = terminal.ModifyKeyFormat

pub type VtMouseShape = terminal.MouseShape

pub type VtProtectedMode = terminal.ProtectedMode

pub type VtStatusLineType = terminal.StatusLineType

pub type VtStatusDisplay = terminal.StatusDisplay

pub type VtEraseDisplay = terminal.EraseDisplay

pub type VtEraseLine = terminal.EraseLine

pub type VtTabClear = terminal.TabClear

pub type VtAttribute = terminal.Attribute

pub type VtReadonlyHandler = terminal.ReadonlyHandler

pub type VtReadonlyStream = terminal.ReadonlyStream

pub type VtScrollbar = terminal.Scrollbar

// V has no nested public module declarations, so the APIs under Zig's
// `lib_vt.input` namespace use an Input prefix at this module boundary.
pub type InputPasteOptions = input.PasteOptions

pub type InputKey = input.Key

pub type InputKeyAction = input.KeyAction

pub type InputKeyEvent = input.KeyEvent

pub type InputKeyMods = input.Mods

pub type InputKeyEncodeOptions = input.Options

pub fn input_is_safe_paste(data string) bool {
	return input.is_safe(data)
}

pub fn input_encode_paste(data string, opts InputPasteOptions) ![3]string {
	return input.paste_encode(data, opts)!.parts()
}

pub fn input_encode_key(event InputKeyEvent, opts InputKeyEncodeOptions) string {
	return input.encode(event, opts)
}

// Package-level APIs that are namespaces in Zig are V modules (`osc`,
// `kitty`, `search`, and so on) and are imported directly by V callers. The
// C-facing wrappers live in the `terminal_c` module; V does not require Zig's
// comptime @export aggregation to make those callable.
