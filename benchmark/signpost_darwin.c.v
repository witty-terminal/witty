module benchmark

import macos

fn benchmark_signpost_begin(ptr voidptr) BenchmarkSignpost {
	macos.signpost_init()
	log := macos.OSLog.create('com.alexander.witty', macos.signpost_category_points_of_interest)
	if isnil(log) {
		return BenchmarkSignpost{}
	}
	id := macos.signpost_id_for_pointer(log, ptr)
	macos.signpost_interval_begin(log, id, 'ghostty')
	return BenchmarkSignpost{
		log:    voidptr(log)
		id:     id
		active: true
	}
}

fn (mut self BenchmarkSignpost) end() {
	if !self.active {
		return
	}
	log := unsafe { &macos.OSLog(self.log) }
	macos.signpost_interval_end(log, self.id, 'ghostty')
	log.release()
	self.active = false
}
