module build_support

import os

// Shared build/runtime locale list, in the original source's significant
// order. Keep it isolated so host generation does not link the app runtime.
pub const locales = ['zh_CN.UTF-8', 'de_DE.UTF-8', 'fr_FR.UTF-8', 'ja_JP.UTF-8',
	'nl_NL.UTF-8', 'nb_NO.UTF-8', 'ru_RU.UTF-8', 'uk_UA.UTF-8', 'pl_PL.UTF-8',
	'ko_KR.UTF-8', 'mk_MK.UTF-8', 'tr_TR.UTF-8', 'id_ID.UTF-8', 'es_BO.UTF-8',
	'es_AR.UTF-8', 'pt_BR.UTF-8', 'ca_ES.UTF-8', 'it_IT.UTF-8', 'bg_BG.UTF-8',
	'ga_IE.UTF-8', 'hu_HU.UTF-8', 'he_IL.UTF-8', 'zh_TW.UTF-8', 'hr_HR.UTF-8', 'lt_LT.UTF-8']

// GhosttyI18n.init. Catalog compilation is a host operation, including when
// the final binary targets another platform.
pub fn (d Driver) install_locales() ! {
	if !d.cfg.i18n { return }
	for locale in locales {
		text := checked_process(d.cfg.root, ['msgfmt', '-o', '-', os.join_path('po', '${locale}.po')])!
		// Preserve the source's trimRight character-set operation on FreeBSD.
		target_locale := if d.cfg.target.os == 'freebsd' { locale.trim_right('.UTF-8') } else { locale }
		d.install_text('share/locale/${target_locale}/LC_MESSAGES/com.alexander.witty.mo', text)!
	}
}

pub fn (d Driver) update_translations() ! {
	if !d.cfg.i18n { return error('cannot update translations when i18n is disabled') }
	mut args := ['xgettext', '--language=JavaScript', '--from-code=UTF-8', '--add-comments=Translators',
		'--keyword=translate', '--package-name=com.alexander.witty',
		'--msgid-bugs-address=m@mitchellh.com', '--copyright-holder="Mitchell Hashimoto, Ghostty contributors"', '-o', '-']
	// Input paths must be relative to the checkout, and source files sorted,
	// because extraction locations become part of the committed catalogs.
	mut sources := os.walk_ext(os.join_path(d.cfg.root, 'apprt', 'ui2_runtime'), '.v')
	sources.sort()
	for path in sources { args << path[d.cfg.root.len + 1..] }
	pot := checked_process(d.cfg.root, args)!
	output := d.cache_path('i18n', 'com.alexander.witty.pot')
	os.mkdir_all(os.dir(output))!
	os.write_file(output, pot)!
	// Generate all outputs before updating source files, like the source's
	// UpdateSourceFiles step. A failed msgmerge cannot leave a partial update.
	mut merged := map[string]string{}
	for locale in locales {
		path := os.join_path('po', '${locale}.po')
		merged[path] = checked_process(d.cfg.root, ['msgmerge', '--quiet', '--no-fuzzy-matching', path, output])!
	}
	os.write_file(os.join_path(d.cfg.root, 'po', 'com.alexander.witty.pot'), pot)!
	for path, text in merged { os.write_file(os.join_path(d.cfg.root, path), text)! }
}
