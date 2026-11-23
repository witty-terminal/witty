module internal_os

import macos
import os

$if macos || ios {
	#include <errno.h>

	#include <pthread.h>

	fn C.pthread_set_qos_class_self_np(qos_class u32, relative_priority int) int

	fn C.pthread_setname_np(name &char) int

	// QosClass is the Darwin pthread quality-of-service class.
	pub enum QosClass as u32 {
		user_interactive = 0x21
		user_initiated   = 0x19
		default_         = 0x15
		utility          = 0x11
		background       = 0x09
		unspecified      = 0x00
	}

	// set_qos_class changes the quality-of-service class of the current thread.
	pub fn set_qos_class(class QosClass) ! {
		result := C.pthread_set_qos_class_self_np(u32(class), 0)
		if result == 0 {
			return
		}
		if result == C.EPERM {
			return error('thread is incompatible with QoS changes')
		}
		panic('unexpected pthread_set_qos_class_self_np error: ${result}')
	}

	// set_thread_name names the current Darwin thread.
	pub fn set_thread_name(name string) {
		C.pthread_setname_np(name.str)
	}

	// is_at_least_version checks the running OS version.
	pub fn is_at_least_version(major i64, minor i64, patch i64) bool {
		return macos.is_at_least_version(major, minor, patch)
	}

	// app_support_dir returns Ghostty's user Application Support path.
	pub fn app_support_dir(sub_path string) !string {
		return common_macos_dir(14, 'com.alexander.witty', sub_path)
	}

	pub fn previous_app_support_dir(sub_path string) !string {
		return common_macos_dir(14, 'com.mitchellh.ghostty', sub_path)
	}

	// cache_dir returns Ghostty's user cache path.
	pub fn cache_dir(sub_path string) !string {
		return common_macos_dir(13, 'com.alexander.witty', sub_path)
	}

	fn common_macos_dir(directory u64, bundle_id string, sub_path string) !string {
		base := macos.user_directory(directory) or {
			return error('Apple directory API failed')
		}
		return os.join_path(base, bundle_id, sub_path)
	}
}
