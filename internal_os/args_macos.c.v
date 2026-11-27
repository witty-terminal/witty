module internal_os

import witty_macos as macos
fn platform_args() []string {
	return macos.process_arguments()
}
