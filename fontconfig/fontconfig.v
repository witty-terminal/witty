module fontconfig

// Fontconfig bindings (Linux/Unix font discovery).
//
// Fontconfig is a library for configuring and customizing font access on
// Linux/Unix systems. It provides font matching, pattern-based font
// specification, and font set management.
//
// Translated from ghostty/pkg/fontconfig. The V wrapper structs each hold
// a single raw fontconfig `handle` pointer; the actual C entry points are
// declared as `fn C.Fc*` below.

// C compiler flags for the fontconfig library.
$if managed_native ? {
	$if !system_fontconfig ? {
		#flag -I@VMODROOT/.witty-build/deps/fontconfig
	}
} $else {
	#flag darwin -I/opt/homebrew/include
	#flag darwin -L/opt/homebrew/lib
	#flag linux -I/usr/include
	#flag -lfontconfig
}

#include <fontconfig/fontconfig.h>

#include "fontconfig_shims.h"

// === C function declarations ===

fn C.FcInit() int

fn C.FcFini()

fn C.FcGetVersion() int

fn C.FcInitLoadConfig() voidptr

fn C.FcInitLoadConfigAndFonts() voidptr

fn C.FcConfigDestroy(config voidptr)

fn C.FcConfigSubstitute(config voidptr, pat voidptr, kind int) int

fn C.FcDefaultSubstitute(pat voidptr)

fn C.FcFontSort(config voidptr, pat voidptr, trim int, csp voidptr, result &int) voidptr

fn C.FcFontRenderPrepare(config voidptr, pat voidptr, font voidptr) voidptr

fn C.FcFontList(config voidptr, pat voidptr, os voidptr) voidptr

fn C.FcPatternCreate() voidptr

fn C.FcNameParse(name &char) voidptr

fn C.FcPatternDestroy(pat voidptr)

fn C.FcPatternDel(pat voidptr, object &char) int

fn C.FcPatternFilter(pat voidptr, os voidptr) voidptr

fn C.FcPatternPrint(pat voidptr)

fn C.FcPatternObjectCount(pat voidptr) int

fn C.FcPatternIterStart(pat voidptr, iter voidptr)

fn C.FcPatternIterNext(pat voidptr, iter voidptr) int

fn C.FcPatternIterIsValid(pat voidptr, iter voidptr) int

fn C.FcPatternIterGetObject(pat voidptr, iter voidptr) &char

fn C.FcPatternIterValueCount(pat voidptr, iter voidptr) int

fn C.vt_fontconfig_pattern_add(pat voidptr, object &char, value voidptr, append int) int

fn C.vt_fontconfig_pattern_get(pat voidptr, object &char, id int, value voidptr) int

fn C.vt_fontconfig_pattern_iter_get_value(pat voidptr, iter voidptr, id int, value voidptr, binding &int) int

fn C.FcFontSetCreate() voidptr

fn C.FcFontSetDestroy(fs voidptr)

fn C.FcFontSetAdd(fs voidptr, pat voidptr) int

fn C.FcFontSetPrint(fs voidptr)

fn C.FcCharSetCreate() voidptr

fn C.FcCharSetDestroy(cs voidptr)

fn C.FcCharSetAddChar(cs voidptr, ucs4 u32) int

fn C.FcCharSetHasChar(cs voidptr, ucs4 u32) int

fn C.FcLangSetCreate() voidptr

fn C.FcLangSetDestroy(ls voidptr)

fn C.FcLangSetAdd(ls voidptr, lang &char) int

fn C.FcLangSetHasLang(ls voidptr, lang &char) int

fn C.FcObjectSetCreate() voidptr

fn C.FcObjectSetDestroy(os voidptr)

fn C.FcObjectSetAdd(os voidptr, object &char) int

fn C.FcRangeDestroy(range voidptr)

// vt_fontconfig_fontset_fonts and vt_fontconfig_fontset_nfont read the
// `fonts`/`nfont` fields out of the opaque FcFontSet struct without us
// having to hard-code the struct layout on the V side.
fn C.vt_fontconfig_fontset_nfont(fs voidptr) int

fn C.vt_fontconfig_fontset_font(fs voidptr, idx int) voidptr

// FcResult values (from fontconfig.h). FcResultMatch is 0.
const fc_result_match = 0

// FcMatchKind values.
const fc_match_pattern = 0
const fc_match_font = 1
const fc_match_scan = 2

// ============================================================
// Config
// ============================================================

// Config represents a fontconfig configuration.
pub struct Config {
	handle voidptr = unsafe { nil }
}

// init_load_config_and_fonts initializes fontconfig and loads the default
// configuration and system fonts.
pub fn init_load_config_and_fonts() Config {
	return Config{
		handle: C.FcInitLoadConfigAndFonts()
	}
}

// init_load_config initializes fontconfig and loads its configuration without
// loading the system font database.
pub fn init_load_config() Config {
	return Config{
		handle: C.FcInitLoadConfig()
	}
}

// destroy releases the fontconfig configuration.
pub fn (c Config) destroy() {
	if !isnil(c.handle) {
		C.FcConfigDestroy(c.handle)
	}
}

pub fn (c Config) cval() voidptr {
	return c.handle
}

// font_sort sorts fonts matching a pattern by closeness.
pub fn (c Config) font_sort(pat &Pattern, trim bool, csp voidptr) FontSortResult {
	mut result := int(0)
	fs := C.FcFontSort(c.handle, pat.handle, if trim { 1 } else { 0 }, csp, &result)
	return FontSortResult{
		result: unsafe { MatchResult(result) }
		fs:     &FontSet{
			handle: fs
		}
	}
}

// font_list returns the fonts matching pat, restricted to the properties in
// objects. The returned set owns its patterns and must be destroyed.
pub fn (c Config) font_list(pat &Pattern, objects &ObjectSet) &FontSet {
	return &FontSet{
		handle: C.FcFontList(c.handle, pat.handle, objects.handle)
	}
}

// substitute_with_pat performs pattern substitution.
pub fn (c Config) substitute_with_pat(pat &Pattern, kind SubstituteKind) bool {
	fc_kind := match kind {
		.pattern { fc_match_pattern }
		.font { fc_match_font }
		.scan { fc_match_scan }
	}
	return C.FcConfigSubstitute(c.handle, pat.handle, fc_kind) != 0
}

// font_render_prepare prepares a pattern for rendering, producing a new
// pattern that combines the search pattern with the matched font.
pub fn (c Config) font_render_prepare(pat &Pattern, font_pat &Pattern) !&Pattern {
	ptr := C.FcFontRenderPrepare(c.handle, pat.handle, font_pat.handle)
	if isnil(ptr) {
		return error('FcFontRenderPrepare failed')
	}
	return &Pattern{
		handle: ptr
	}
}

// ============================================================
// Pattern
// ============================================================

// Pattern represents a fontconfig pattern for font matching.
pub struct Pattern {
	handle voidptr = unsafe { nil }
}

// create creates an empty fontconfig pattern.
pub fn Pattern.create() &Pattern {
	return &Pattern{
		handle: C.FcPatternCreate()
	}
}

// parse creates a pattern from fontconfig's textual name syntax.
pub fn Pattern.parse(value string) &Pattern {
	return &Pattern{
		handle: C.FcNameParse(&char(value.str))
	}
}

// destroy releases the pattern.
pub fn (p &Pattern) destroy() {
	if !isnil(p.handle) {
		C.FcPatternDestroy(p.handle)
	}
}

pub fn (p &Pattern) cval() voidptr {
	return p.handle
}

// add adds a typed value to the pattern.
pub fn (p &Pattern) add(prop Property, val Value, append bool) bool {
	object := prop.cval()
	raw := val.cval()
	return C.vt_fontconfig_pattern_add(p.handle, &char(object.str), voidptr(&raw), if append {
		1
	} else {
		0
	}) != 0
}

// default_substitute fills in default values for the pattern.
pub fn (p &Pattern) default_substitute() {
	C.FcDefaultSubstitute(p.handle)
}

// get retrieves a property value from the pattern at the given index.
pub fn (p &Pattern) get(prop Property, idx int) !Value {
	object := prop.cval()
	mut raw := RawValue{}
	result := C.vt_fontconfig_pattern_get(p.handle, &char(object.str), idx, voidptr(&raw))
	if result != fc_result_match {
		return result_error(result, 'FcPatternGet(${object})')
	}
	return Value.init(&raw)
}

// delete removes every value for prop from the pattern.
pub fn (p &Pattern) delete(prop Property) bool {
	object := prop.cval()
	return C.FcPatternDel(p.handle, &char(object.str)) != 0
}

// filter copies only properties listed in objects into a new pattern.
pub fn (p &Pattern) filter(objects &ObjectSet) &Pattern {
	return &Pattern{
		handle: C.FcPatternFilter(p.handle, objects.handle)
	}
}

// print writes fontconfig's diagnostic representation of this pattern.
pub fn (p &Pattern) print() {
	C.FcPatternPrint(p.handle)
}

// object_iterator iterates over every object and value in this pattern.
pub fn (p &Pattern) object_iterator() PatternObjectIterator {
	return PatternObjectIterator{
		pattern: p.handle
	}
}

struct PatternIterStorage {
mut:
	dummy1 voidptr = unsafe { nil }
	dummy2 voidptr = unsafe { nil }
}

pub struct PatternObjectIterator {
	pattern voidptr = unsafe { nil }
mut:
	storage PatternIterStorage
	started bool
}

// next moves to the next object. The first call selects the first object.
pub fn (mut it PatternObjectIterator) next() bool {
	if !it.started {
		it.started = true
		if C.FcPatternObjectCount(it.pattern) == 0 {
			return false
		}
		C.FcPatternIterStart(it.pattern, voidptr(&it.storage))
		return C.FcPatternIterIsValid(it.pattern, voidptr(&it.storage)) != 0
	}
	return C.FcPatternIterNext(it.pattern, voidptr(&it.storage)) != 0
}

// object returns the current object's fontconfig name.
pub fn (it &PatternObjectIterator) object() string {
	ptr := C.FcPatternIterGetObject(it.pattern, voidptr(&it.storage))
	if isnil(ptr) {
		return ''
	}
	return unsafe { cstring_to_vstring(ptr) }
}

// value_len returns the number of values for the current object.
pub fn (it &PatternObjectIterator) value_len() int {
	return C.FcPatternIterValueCount(it.pattern, voidptr(&it.storage))
}

pub fn (it &PatternObjectIterator) value_iterator() PatternValueIterator {
	return PatternValueIterator{
		pattern: it.pattern
		storage: it.storage
		max:     it.value_len()
	}
}

pub struct PatternValueIterator {
	pattern voidptr = unsafe { nil }
	storage PatternIterStorage
	max     int
mut:
	id int
}

pub struct PatternValueEntry {
pub:
	result  MatchResult
	value   Value
	binding ValueBinding
}

pub fn (mut it PatternValueIterator) next() ?PatternValueEntry {
	if it.id >= it.max {
		return none
	}
	mut raw := RawValue{}
	mut binding := 0
	result := C.vt_fontconfig_pattern_iter_get_value(it.pattern, voidptr(&it.storage),
		it.id, voidptr(&raw), &binding)
	it.id++
	return PatternValueEntry{
		result:  unsafe { MatchResult(result) }
		value:   Value.init(&raw)
		binding: unsafe { ValueBinding(binding) }
	}
}

// ============================================================
// FontSet
// ============================================================

// FontSet holds a set of font patterns.
pub struct FontSet {
	handle voidptr = unsafe { nil }
}

// create creates an empty font set.
pub fn FontSet.create() &FontSet {
	return &FontSet{
		handle: C.FcFontSetCreate()
	}
}

// destroy releases the font set.
pub fn (fs &FontSet) destroy() {
	if !isnil(fs.handle) {
		C.FcFontSetDestroy(fs.handle)
	}
}

pub fn (fs &FontSet) cval() voidptr {
	return fs.handle
}

// add transfers a pattern into this font set.
pub fn (fs &FontSet) add(pattern &Pattern) bool {
	return C.FcFontSetAdd(fs.handle, pattern.handle) != 0
}

pub fn (fs &FontSet) print() {
	C.FcFontSetPrint(fs.handle)
}

// fonts returns the font patterns in this set.
pub fn (fs &FontSet) fonts() []&Pattern {
	if isnil(fs.handle) {
		return []&Pattern{}
	}
	n := C.vt_fontconfig_fontset_nfont(fs.handle)
	mut out := []&Pattern{cap: n}
	for i in 0 .. n {
		ptr := C.vt_fontconfig_fontset_font(fs.handle, i)
		out << &Pattern{
			handle: ptr
		}
	}
	return out
}

// ============================================================
// CharSet
// ============================================================

// CharSet represents a set of Unicode codepoints.
pub struct CharSet {
	handle voidptr = unsafe { nil }
}

// create creates an empty character set.
pub fn CharSet.create() &CharSet {
	return &CharSet{
		handle: C.FcCharSetCreate()
	}
}

// destroy releases the character set.
pub fn (cs &CharSet) destroy() {
	if !isnil(cs.handle) {
		C.FcCharSetDestroy(cs.handle)
	}
}

// add_char adds a codepoint to the character set.
pub fn (cs &CharSet) add_char(cp u32) bool {
	return C.FcCharSetAddChar(cs.handle, cp) != 0
}

// has_char reports whether this character set contains cp.
pub fn (cs &CharSet) has_char(cp u32) bool {
	return !isnil(cs) && !isnil(cs.handle) && C.FcCharSetHasChar(cs.handle, cp) != 0
}

pub fn (cs &CharSet) cval() voidptr {
	return cs.handle
}

pub fn (cs &CharSet) cval_const() voidptr {
	return cs.handle
}

// ============================================================
// LangSet
// ============================================================

// LangSet represents a set of languages.
pub struct LangSet {
	handle voidptr = unsafe { nil }
}

pub fn LangSet.create() &LangSet {
	return &LangSet{
		handle: C.FcLangSetCreate()
	}
}

pub fn (ls &LangSet) destroy() {
	if !isnil(ls.handle) {
		C.FcLangSetDestroy(ls.handle)
	}
}

pub fn (ls &LangSet) add_lang(lang string) bool {
	return C.FcLangSetAdd(ls.handle, &char(lang.str)) != 0
}

// has_lang reports whether lang is an exact match in this language set.
pub fn (ls &LangSet) has_lang(lang string) bool {
	return !isnil(ls) && !isnil(ls.handle) && C.FcLangSetHasLang(ls.handle, &char(lang.str)) == 0
}

pub fn (ls &LangSet) cval() voidptr {
	return ls.handle
}

pub fn (ls &LangSet) cval_const() voidptr {
	return ls.handle
}

// ============================================================
// ObjectSet, Matrix, and Range
// ============================================================

pub struct ObjectSet {
	handle voidptr = unsafe { nil }
}

pub fn ObjectSet.create() &ObjectSet {
	return &ObjectSet{
		handle: C.FcObjectSetCreate()
	}
}

pub fn (os &ObjectSet) destroy() {
	if !isnil(os.handle) {
		C.FcObjectSetDestroy(os.handle)
	}
}

pub fn (os &ObjectSet) add(prop Property) bool {
	object := prop.cval()
	return C.FcObjectSetAdd(os.handle, &char(object.str)) != 0
}

pub fn (os &ObjectSet) cval() voidptr {
	return os.handle
}

pub struct Matrix {
pub:
	xx f64
	xy f64
	yx f64
	yy f64
}

pub struct Range {
	handle voidptr = unsafe { nil }
}

pub fn (r &Range) destroy() {
	if !isnil(r.handle) {
		C.FcRangeDestroy(r.handle)
	}
}

pub fn (r &Range) cval() voidptr {
	return r.handle
}

// ============================================================
// Enums and types
// ============================================================

// Property identifies every fontconfig pattern property exported by Ghostty's
// wrapper. cval removes underscores to produce Fontconfig's object names.
pub enum Property as u8 {
	family
	style
	slant
	weight
	size
	aspect
	pixel_size
	spacing
	foundry
	antialias
	hinting
	hint_style
	vertical_layout
	autohint
	global_advance
	width
	file
	index
	ft_face
	rasterizer
	outline
	scalable
	color
	variable
	scale
	symbol
	dpi
	rgba
	minspace
	source
	charset
	lang
	fontversion
	fullname
	familylang
	stylelang
	fullnamelang
	capability
	embolden
	embedded_bitmap
	decorative
	lcd_filter
	font_features
	font_variations
	namelang
	prgname
	hash
	postscript_name
	font_has_hint
	order
}

// cval returns the fontconfig object string for this property.
pub fn (p Property) cval() string {
	return p.str().replace('_', '')
}

// Type is the tag of Fontconfig's FcValue union.
pub enum Type as i32 {
	unknown = -1
	void_
	integer
	double_
	string_
	bool_
	matrix
	char_set
	ft_face
	lang_set
	range
}

// Value is the translated FcValue tagged union.
pub type Value = ValueBool
	| ValueCharSet
	| ValueDouble
	| ValueFtFace
	| ValueInteger
	| ValueLangSet
	| ValueMatrix
	| ValueRange
	| ValueString
	| ValueUnknown
	| ValueVoid

pub struct ValueUnknown {}

pub struct ValueVoid {}

pub struct ValueInteger {
pub:
	value i32
}

pub struct ValueDouble {
pub:
	value f64
}

pub struct ValueString {
pub:
	value string
}

pub struct ValueBool {
pub:
	value bool
}

pub struct ValueMatrix {
pub:
	value &Matrix = unsafe { nil }
}

pub struct ValueCharSet {
pub:
	value &CharSet = unsafe { nil }
}

pub struct ValueFtFace {
pub:
	value voidptr = unsafe { nil }
}

pub struct ValueLangSet {
pub:
	value &LangSet = unsafe { nil }
}

pub struct ValueRange {
pub:
	value &Range = unsafe { nil }
}

// The tag of the active value variant.
pub fn (self Value) tag() Type {
	return match self {
		ValueUnknown { .unknown }
		ValueVoid { .void_ }
		ValueInteger { .integer }
		ValueDouble { .double_ }
		ValueString { .string_ }
		ValueBool { .bool_ }
		ValueMatrix { .matrix }
		ValueCharSet { .char_set }
		ValueFtFace { .ft_face }
		ValueLangSet { .lang_set }
		ValueRange { .range }
	}
}

struct RawValue {
mut:
	typ           i32
	integer_value i32
	double_value  f64
	string_value  &char = unsafe { nil }
	bool_value    i32
	pointer_value voidptr = unsafe { nil }
}

// cval converts the value to the FcValue shim layout.
fn (self Value) cval() RawValue {
	mut result := RawValue{
		typ: i32(self.tag())
	}
	match self {
		ValueUnknown, ValueVoid {}
		ValueInteger { result.integer_value = self.value }
		ValueDouble { result.double_value = self.value }
		ValueString { result.string_value = &char(self.value.str) }
		ValueBool { result.bool_value = if self.value { 1 } else { 0 } }
		ValueMatrix { result.pointer_value = voidptr(self.value) }
		ValueCharSet {
			if !isnil(self.value) {
				result.pointer_value = self.value.handle
			}
		}
		ValueFtFace { result.pointer_value = self.value }
		ValueLangSet {
			if !isnil(self.value) {
				result.pointer_value = self.value.handle
			}
		}
		ValueRange {
			if !isnil(self.value) {
				result.pointer_value = self.value.handle
			}
		}
	}
	return result
}

// Value.init converts an FcValue shim value into the tagged union.
fn Value.init(cvalue &RawValue) Value {
	tag := unsafe { Type(cvalue.typ) }
	match tag {
		.unknown {
			return ValueUnknown{}
		}
		.void_ {
			return ValueVoid{}
		}
		.string_ {
			return ValueString{
				value: if isnil(cvalue.string_value) {
					''
				} else {
					unsafe { cstring_to_vstring(cvalue.string_value) }
				}
			}
		}
		.integer {
			return ValueInteger{
				value: i32(cvalue.integer_value)
			}
		}
		.double_ {
			return ValueDouble{
				value: cvalue.double_value
			}
		}
		.bool_ {
			return ValueBool{
				value: cvalue.bool_value != 0
			}
		}
		.matrix {
			return ValueMatrix{
				value: unsafe { &Matrix(cvalue.pointer_value) }
			}
		}
		.char_set {
			return ValueCharSet{
				value: &CharSet{
					handle: cvalue.pointer_value
				}
			}
		}
		.ft_face {
			return ValueFtFace{
				value: cvalue.pointer_value
			}
		}
		.lang_set {
			return ValueLangSet{
				value: &LangSet{
					handle: cvalue.pointer_value
				}
			}
		}
		.range {
			return ValueRange{
				value: &Range{
					handle: cvalue.pointer_value
				}
			}
		}
	}
}

pub enum SubstituteKind as u32 {
	pattern
	font
	scan
}

pub type MatchKind = SubstituteKind

// Weight constants for fontconfig (matching FC_WEIGHT_* values).
pub enum Weight as u32 {
	thin       = 0
	extralight = 40
	light      = 50
	demilight  = 55
	book       = 75
	regular    = 80
	medium     = 100
	demibold   = 180
	bold       = 200
	extrabold  = 205
	black      = 210
	extrablack = 215
}

// Slant constants for fontconfig (matching FC_SLANT_* values).
pub enum Slant as u32 {
	roman   = 0
	italic  = 100
	oblique = 110
}

// Spacing constants for fontconfig (matching FC_* spacing values).
pub enum Spacing as u32 {
	proportional = 0
	dual         = 90
	mono         = 100
	charcell     = 110
}

// FontSortResult holds the result of a font sort operation.
pub struct FontSortResult {
pub:
	result MatchResult
	fs     &FontSet = unsafe { nil }
}

// MatchResult indicates the outcome of a font match.
pub enum MatchResult as u32 {
	match_
	no_match
	type_mismatch
	no_id
	out_of_memory
}

pub type Result = MatchResult

pub fn (result MatchResult) to_error() ! {
	match result {
		.match_ {}
		.no_match { return error('fontconfig: no match') }
		.type_mismatch { return error('fontconfig: type mismatch') }
		.no_id { return error('fontconfig: no id') }
		.out_of_memory { return error('fontconfig: out of memory') }
	}
}

pub enum ValueBinding as i32 {
	weak
	strong
	same
}

fn result_error(result int, operation string) IError {
	return match result {
		1 { error('${operation}: no match') }
		2 { error('${operation}: type mismatch') }
		3 { error('${operation}: no id') }
		4 { error('${operation}: out of memory') }
		else { error('${operation}: unknown result ${result}') }
	}
}

// fc_init initializes the fontconfig library.
// Safe to call multiple times and concurrently.
pub fn fc_init() bool {
	return C.FcInit() != 0
}

// fini finalizes Fontconfig's process-wide state.
pub fn fini() {
	C.FcFini()
}

// version returns Fontconfig's compile-time-compatible runtime version.
pub fn version() u32 {
	return u32(C.FcGetVersion())
}
