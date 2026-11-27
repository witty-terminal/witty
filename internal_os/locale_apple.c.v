module internal_os

import witty_macos as macos
$if macos || ios {
	import log

	fn macos_system_locale() ?macos.SystemLocale {
		return macos.system_locale()
	}

	fn macos_preferred_languages() []string {
		return macos.preferred_languages()
	}

	fn set_lang_from_cocoa() {
		locale := macos_system_locale() or {
			log.warn('languageCode or countryCode not found. Locale may be incorrect.')
			return
		}
		lang_value := '${locale.language}_${locale.country}.UTF-8'
		// The pinned implementation uses a 128-byte fixed buffer.
		if lang_value.len >= 128 {
			log.warn('error setting locale from system. err=NoSpaceLeft')
			return
		}
		log.info('detected system locale=${lang_value}')
		if setenv('LANG', lang_value) < 0 {
			log.warn('error setting locale env var')
			return
		}

		preferred := macos_preferred_languages()
		mut canonical := []string{cap: preferred.len}
		mut total_len := 0
		for language in preferred {
			if language.len == 0 {
				log.warn('failed to convert a preferred language to UTF-8')
				continue
			}
			value := canonicalize_locale(language) + '.UTF-8'
			total_len += value.len
			if canonical.len > 0 {
				total_len++
			}
			// Match upstream's 1024-byte buffer including its terminator.
			if total_len >= 1024 {
				log.warn('error getting preferred languages. err=NoSpaceLeft')
				return
			}
			canonical << value
		}
		if canonical.len > 0 {
			value := canonical.join(':')
			log.debug('setting LANGUAGE from preferred languages value=${value}')
			setenv('LANGUAGE', value)
		}
	}
}
