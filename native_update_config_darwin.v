module main

import configpkg
import witty_macos as macos
fn native_update_config(config &configpkg.Config) macos.NativeUpdateConfig {
	mut policy := ?int(none)
	if value := config.auto_update { policy = int(value) }
	return macos.NativeUpdateConfig{
		auto_update: policy
		channel: if channel := config.auto_update_channel { channel.str() } else { 'stable' }
	}
}
