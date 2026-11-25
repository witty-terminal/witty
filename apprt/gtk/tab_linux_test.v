module gtk

import configpkg

fn test_tab_computed_title_uses_config_title_and_bell_features() {
	mut inner := configpkg.Config.default_config()
	inner.title = 'Configured Title'
	mut cfg := config_new(inner)
	mut tab := Tab{}

	assert tab.computed_title(cfg, none, none, false, false) == 'Configured Title'
	assert tab.computed_title(cfg, 'Terminal Title', none, true, true) == '🔔 🔍 Terminal Title'
	assert tab.computed_title(cfg, 'Terminal Title', 'Override', false, false) == 'Override'
	tab.title_override = 'Tab override'
	assert tab.computed_title(cfg, 'Terminal Title', 'Override', true, true) == '🔔 🔍 Tab override'
	tab.title_override = none

	cfg.get_mut().bell_features = configpkg.BellFeatures.init(false, false, true, false, false)
	assert tab.computed_title(cfg, 'Terminal Title', none, false, true) == 'Terminal Title'
	cfg.unref()
}

fn test_tab_computed_title_uses_source_fallback_without_config() {
	tab := Tab{}
	assert tab.computed_title(unsafe { nil }, none, none, false, false) == 'Witty'
	assert tab.computed_title(unsafe { nil }, 'Terminal Title', none, false, false) == 'Terminal Title'
	assert tab.computed_title(unsafe { nil }, 'Terminal Title', 'Override', false, false) == 'Override'
}
