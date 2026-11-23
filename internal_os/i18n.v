module internal_os

import math
import log
import os

#flag -I @VMODROOT/internal_os
#include "i18n_shims.h"

const ghostty_gettext_domain = 'com.alexander.witty'

// Supported application locales. The order is significant: callers with
// incomplete locale information use the first matching language.
pub const supported_locales = [
	'zh_CN.UTF-8',
	'de_DE.UTF-8',
	'fr_FR.UTF-8',
	'ja_JP.UTF-8',
	'nl_NL.UTF-8',
	'nb_NO.UTF-8',
	'ru_RU.UTF-8',
	'uk_UA.UTF-8',
	'pl_PL.UTF-8',
	'ko_KR.UTF-8',
	'mk_MK.UTF-8',
	'tr_TR.UTF-8',
	'id_ID.UTF-8',
	'es_BO.UTF-8',
	'es_AR.UTF-8',
	'pt_BR.UTF-8',
	'ca_ES.UTF-8',
	'it_IT.UTF-8',
	'bg_BG.UTF-8',
	'ga_IE.UTF-8',
	'hu_HU.UTF-8',
	'he_IL.UTF-8',
	'zh_TW.UTF-8',
	'hr_HR.UTF-8',
	'lt_LT.UTF-8',
]!

$if !no_i18n ? {
	// Managed builds link the per-target archive from the native graph.
	$if !managed_native ? {
		#flag darwin @VMODROOT/.witty-build/native/libintl.a
	}
	#flag freebsd -lintl
}

fn C.bindtextdomain(&char, &char) &char
fn C.textdomain(&char) &char
fn C.dgettext(&char, &char) &char
fn C._libintl_locale_name_canonicalize(&char)

// init binds the same linked gettext implementation selected by Ghostty.
pub fn init(resources_dir string) ! {
	$if no_i18n ? { return } $else $if i18n ? {
		i18n_init_enabled(resources_dir)!
	} $else $if macos || ios || ((linux || freebsd) && glibc) {
		i18n_init_enabled(resources_dir)!
	}
}

fn i18n_init_enabled(resources_dir string) ! {
	$if windows { return }
	share_dir := i18n_share_dir(resources_dir) or { return error('InvalidResourcesDir') }
	locale_dir := os.join_path(share_dir, 'locale')
	if locale_dir.len >= 4096 { return error('OutOfMemory') }
	log.debug('binding domain=${ghostty_gettext_domain} path=${locale_dir}')
	if isnil(C.bindtextdomain(&char(ghostty_gettext_domain.str), &char(locale_dir.str))) {
		return error('OutOfMemory')
	}
}

// i18n_share_dir is std.fs.path.dirname's POSIX behavior. In particular, a
// basename and a basename with trailing slashes have no directory component;
// os.dir maps both to a usable string and would hide InvalidResourcesDir.
fn i18n_share_dir(path string) ?string {
	if path.len == 0 {
		return none
	}
	mut end := path.len - 1
	for path[end] == `/` {
		if end == 0 {
			return none
		}
		end--
	}
	for path[end] != `/` {
		if end == 0 {
			return none
		}
		end--
	}
	if end == 0 {
		return if path[0] == `/` { '/' } else { none }
	}
	return path[..end]
}

pub fn init_global_domain() ! {
	$if no_i18n ? { return } $else $if i18n ? {
		i18n_global_domain_enabled()!
	} $else $if macos || ios || ((linux || freebsd) && glibc) {
		i18n_global_domain_enabled()!
	}
}

fn i18n_global_domain_enabled() ! {
	if isnil(C.textdomain(&char(ghostty_gettext_domain.str))) { return error('OutOfMemory') }
}

pub fn translate_c(msgid &char) &char {
	$if no_i18n ? { return unsafe { msgid } } $else $if i18n ? {
		return i18n_translate_enabled(msgid)
	} $else $if macos || ios || ((linux || freebsd) && glibc) {
		return i18n_translate_enabled(msgid)
	} $else { return unsafe { msgid } }
}

fn i18n_translate_enabled(msgid &char) &char {
	return C.dgettext(&char(ghostty_gettext_domain.str), msgid)
}

pub fn translate(msgid string) string {
	return unsafe { cstring_to_vstring(translate_c(&char(msgid.str))) }
}

// static_locale is the V equivalent of Ghostty's compile-time locale
// validator. V cannot return an input-dependent comptime string, so invalid
// callers fail immediately when this helper is evaluated.
pub fn static_locale(value string) string {
	for locale in supported_locales {
		if locale == value {
			return locale
		}
	}
	panic('unsupported locale: ${value}')
}

// canonicalize_locale_into is the original bounded in-place wrapper around
// gettext's unchanged gnulib canonicalizer. The Chinese override deliberately
// requires three components; two-component spellings go through gnulib.
pub fn canonicalize_locale_into(mut buffer []u8, locale string) !string {
	$if no_i18n ? {
		return copy_locale(mut buffer, locale)
	} $else $if i18n ? {
		return canonicalize_locale_enabled(mut buffer, locale)
	} $else $if macos || ios || ((linux || freebsd) && glibc) {
		return canonicalize_locale_enabled(mut buffer, locale)
	} $else { return copy_locale(mut buffer, locale) }
}

fn copy_locale(mut buffer []u8, locale string) !string {
	if buffer.len < locale.len + 1 { return error('NoSpaceLeft') }
	copy(mut buffer[..locale.len], locale.bytes())
	buffer[locale.len] = 0
	return buffer[..locale.len].bytestr()
}

fn canonicalize_locale_enabled(mut buffer []u8, locale string) !string {
	if fixed := fix_zh_locale(locale) {
		if buffer.len < fixed.len + 1 { return error('NoSpaceLeft') }
		copy(mut buffer[..fixed.len], fixed.bytes())
		buffer[fixed.len] = 0
		return buffer[..fixed.len].bytestr()
	}
	if buffer.len < math.max(16, locale.len + 1) { return error('NoSpaceLeft') }
	copy(mut buffer[..locale.len], locale.bytes())
	buffer[locale.len] = 0
	C._libintl_locale_name_canonicalize(unsafe { &char(buffer.data) })
	mut len := 0
	for len < buffer.len && buffer[len] != 0 { len++ }
	return buffer[..len].bytestr()
}

pub fn canonicalize_locale(locale string) string {
	mut buffer := []u8{len: math.max(16, locale.len + 1)}
	return canonicalize_locale_into(mut buffer, locale) or { panic(err) }
}

fn fix_zh_locale(locale string) ?string {
	parts := locale.split('-')
	if parts.len < 3 || parts[0] != 'zh' { return none }
	if parts[1] == 'Hans' {
		return if parts[2] == 'SG' { 'zh_SG' } else { 'zh_CN' }
	}
	if parts[1] == 'Hant' {
		return match parts[2] { 'MO' { 'zh_MO' } 'HK' { 'zh_HK' } else { 'zh_TW' } }
	}
	return none
}

// The source linked library has process lifetime and no shutdown hook.
pub fn shutdown_i18n() {}
