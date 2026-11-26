module cli

import internal_os

fn platform_version_lines() []string {
	kernel := internal_os.get_kernel_info() or { 'Kernel information unavailable' }
	return [
		'  - kernel version: ${kernel}',
		'  - desktop env   : ${internal_os.desktop_environment()}',
	]
}
