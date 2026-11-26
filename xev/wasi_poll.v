module xev

// src/backend/wasi_poll.zig, locked libxev 34fa508. These backend types are
// available for explicit API use on every host; the platform default API
// selects them on wasm32_wasi. Kernel calls are emitted only when used.
import sync.stdatomic as _
import time

$if wasm32_wasi {
	#include <wasi/api.h>
}

$if !windows {
	fn C.__wasi_clock_time_get(id u32, precision u64, timestamp &u64) u16
	fn C.__wasi_poll_oneoff(subscriptions voidptr, events voidptr, count uint, event_count &uint) u16
	fn C.__wasi_sock_shutdown(socket u32, how u8) u16
	fn C.__wasi_sock_accept(socket u32, flags u16, accepted &u32) u16
	fn C.__wasi_sock_recv(socket u32, iovs voidptr, iov_count uint, flags u16, received &uint, returned_flags &u16) u16
	fn C.__wasi_sock_send(socket u32, iovs voidptr, iov_count uint, flags u16, sent &uint) u16
	fn C.__wasi_fd_read(fd u32, iovs voidptr, count uint, received &uint) u16
	fn C.__wasi_fd_pread(fd u32, iovs voidptr, count uint, offset u64, received &uint) u16
	fn C.__wasi_fd_write(fd u32, iovs voidptr, count uint, sent &uint) u16
	fn C.__wasi_fd_pwrite(fd u32, iovs voidptr, count uint, offset u64, sent &uint) u16
	fn C.__wasi_fd_close(fd u32) u16

	// std.os.wasi extern ABI. The union keeps the alignment and clock/FD overlap.
	pub struct WasiSubscriptionClock {
	pub mut:
		id        u32
		timeout   u64
		precision u64
		flags     u16
	}

	pub struct WasiSubscriptionFd {
	pub mut:
		fd u32
	}

	pub union WasiSubscriptionValue {
	pub mut:
		clock    WasiSubscriptionClock
		fd_read  WasiSubscriptionFd
		fd_write WasiSubscriptionFd
	}

	pub struct WasiSubscriptionPayload {
	pub mut:
		tag u8
		u   WasiSubscriptionValue
	}

	pub struct WasiSubscription {
	pub mut:
		userdata u64
		u        WasiSubscriptionPayload
	}

	pub struct WasiEventFdReadWrite {
	pub mut:
		nbytes u64
		flags  u16
	}

	pub struct WasiEvent {
	pub mut:
		userdata     u64
		error_       u16
		type_        u8
		fd_readwrite WasiEventFdReadWrite
	}

	struct WasiIovec {
		base voidptr
		len  uint
	}

	pub const wasi_threaded = $if wasm_threads ? { true } $else { false }

	pub fn wasi_poll_available() bool {
		return $if wasm32_wasi { true } $else { false }
	}

	pub type WasiCallback = fn (ud voidptr, loop &WasiLoop, c &WasiCompletion, result WasiResult) CallbackAction

	pub fn wasi_noop_callback(_ voidptr, _ &WasiLoop, _ &WasiCompletion, _ WasiResult) CallbackAction {
		return .disarm
	}

	pub enum WasiCompletionStateFlag as u8 {
		dead
		adding
		deleting
		active
	}

	pub struct WasiCompletionFlags {
	pub mut:
		value u8
	}

	pub fn (f WasiCompletionFlags) state() WasiCompletionStateFlag {
		return unsafe { WasiCompletionStateFlag(f.value & 7) }
	}

	pub fn (mut f WasiCompletionFlags) set_state(s WasiCompletionStateFlag) { f.value = u8(s) }

	pub enum WasiTimerTrigger as u8 {
		expiration
		cancel
		request
	}

	pub type WasiReadBuffer = ReadBufferArray | ReadBufferSlice
	pub type WasiWriteBuffer = WriteBufferArray | WriteBufferSlice

	fn (self &WasiReadBuffer) slice_ptr() []u8 {
		return match self {
			ReadBufferSlice { self.slice }
			ReadBufferArray { unsafe { (&self.array[0]).vbytes(32) } }
		}
	}

	fn (self &WasiWriteBuffer) bytes() []u8 {
		return match self {
			WriteBufferSlice { self.slice }
			WriteBufferArray { unsafe { (&self.array[0]).vbytes(int(self.len)) } }
		}
	}

	pub enum WasiOperationType as u8 {
		noop
		cancel
		accept
		read
		pread
		write
		pwrite
		send
		recv
		shutdown
		close
		timer
		async_wait
	}

	pub type WasiOperation = WasiNoopOp
		| WasiCancelOp
		| WasiAcceptOp
		| WasiReadOp
		| WasiPReadOp
		| WasiWriteOp
		| WasiPWriteOp
		| WasiSendOp
		| WasiRecvOp
		| WasiShutdownOp
		| WasiCloseOp
		| WasiHeapTimer
		| WasiAsyncWaitOp

	pub struct WasiNoopOp {
	}

	pub struct WasiCancelOp {
	pub mut:
		c &WasiCompletion = unsafe { nil }
	}

	pub struct WasiAcceptOp {
	pub mut:
		socket int
	}

	pub struct WasiReadOp {
	pub mut:
		fd     int
		buffer WasiReadBuffer
	}

	pub struct WasiPReadOp {
	pub mut:
		fd     int
		buffer WasiReadBuffer
		offset u64
	}

	pub struct WasiWriteOp {
	pub mut:
		fd     int
		buffer WasiWriteBuffer
	}

	pub struct WasiPWriteOp {
	pub mut:
		fd     int
		buffer WasiWriteBuffer
		offset u64
	}

	pub struct WasiSendOp {
	pub mut:
		fd     int
		buffer WasiWriteBuffer
	}

	pub struct WasiRecvOp {
	pub mut:
		fd     int
		buffer WasiReadBuffer
	}

	pub struct WasiShutdownOp {
	pub mut:
		socket int
		how    ShutdownHow = .both
	}

	pub struct WasiCloseOp {
	pub mut:
		fd int
	}

	pub struct WasiHeapTimer {
	pub mut:
		next  u64
		reset ?u64
		heap  IntrusiveHeapField[WasiHeapTimer]
		c     &WasiCompletion = unsafe { nil }
	}

	pub struct WasiAsyncWaitOp {
	pub mut:
		wakeup u8
	}

	pub fn (op WasiOperation) tag() WasiOperationType {
		return match op {
			WasiNoopOp { .noop }
			WasiCancelOp { .cancel }
			WasiAcceptOp { .accept }
			WasiReadOp { .read }
			WasiPReadOp { .pread }
			WasiWriteOp { .write }
			WasiPWriteOp { .pwrite }
			WasiSendOp { .send }
			WasiRecvOp { .recv }
			WasiShutdownOp { .shutdown }
			WasiCloseOp { .close }
			WasiHeapTimer { .timer }
			WasiAsyncWaitOp { .async_wait }
		}
	}

	pub type WasiResult = WasiNoopResult
		| WasiCancelResult
		| WasiAcceptResult
		| WasiReadResult
		| WasiPReadResult
		| WasiWriteResult
		| WasiPWriteResult
		| WasiSendResult
		| WasiRecvResult
		| WasiShutdownResult
		| WasiCloseResult
		| WasiTimerResult
		| WasiAsyncWaitResult

	pub struct WasiNoopResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct WasiCancelResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct WasiAcceptResult {
	pub mut:
		err    ?ErrorKind
		socket int
	}

	pub struct WasiReadResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct WasiPReadResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct WasiWriteResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct WasiPWriteResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct WasiSendResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct WasiRecvResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct WasiShutdownResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct WasiCloseResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct WasiTimerResult {
	pub mut:
		err   ?ErrorKind
		timer WasiTimerTrigger
	}

	pub struct WasiAsyncWaitResult {
	pub mut:
		err ?ErrorKind
	}

	pub fn (r WasiResult) tag() WasiOperationType {
		return match r {
			WasiNoopResult { .noop }
			WasiCancelResult { .cancel }
			WasiAcceptResult { .accept }
			WasiReadResult { .read }
			WasiPReadResult { .pread }
			WasiWriteResult { .write }
			WasiPWriteResult { .pwrite }
			WasiSendResult { .send }
			WasiRecvResult { .recv }
			WasiShutdownResult { .shutdown }
			WasiCloseResult { .close }
			WasiTimerResult { .timer }
			WasiAsyncWaitResult { .async_wait }
		}
	}

	fn wasi_result_kind(tag WasiOperationType, kind ErrorKind) WasiResult {
		return match tag {
			.noop { WasiNoopResult{ err: kind } }
			.cancel { WasiCancelResult{ err: kind } }
			.accept { WasiAcceptResult{ err: kind } }
			.read { WasiReadResult{ err: kind } }
			.pread { WasiPReadResult{ err: kind } }
			.write { WasiWriteResult{ err: kind } }
			.pwrite { WasiPWriteResult{ err: kind } }
			.send { WasiSendResult{ err: kind } }
			.recv { WasiRecvResult{ err: kind } }
			.shutdown { WasiShutdownResult{ err: kind } }
			.close { WasiCloseResult{ err: kind } }
			.timer { WasiTimerResult{ err: kind } }
			.async_wait { WasiAsyncWaitResult{ err: kind } }
		}
	}

	fn wasi_result_n(tag WasiOperationType, n uint) WasiResult {
		return match tag {
			.read { WasiReadResult{ n: n } }
			.pread { WasiPReadResult{ n: n } }
			.write { WasiWriteResult{ n: n } }
			.pwrite { WasiPWriteResult{ n: n } }
			.send { WasiSendResult{ n: n } }
			.recv { WasiRecvResult{ n: n } }
			else { panic('result has no byte count') }
		}
	}

	fn wasi_result_bytes(r WasiResult) uint {
		return match r {
			WasiReadResult { r.n }
			WasiPReadResult { r.n }
			WasiWriteResult { r.n }
			WasiPWriteResult { r.n }
			WasiSendResult { r.n }
			WasiRecvResult { r.n }
			else { panic('result has no byte count') }
		}
	}

	@[heap]
	pub struct WasiCompletion {
	pub mut:
		op        WasiOperation = WasiNoopOp{}
		userdata  voidptr
		callback  WasiCallback = wasi_noop_callback
		flags     WasiCompletionFlags
		next      &WasiCompletion = unsafe { nil }
		batch_idx uint
	}

	pub fn (self &WasiCompletion) state() CompletionState {
		return match self.flags.state() {
			.dead { .dead }
			.adding, .deleting, .active { .active }
		}
	}

	fn wasi_timer_less(a &WasiHeapTimer, b &WasiHeapTimer) bool { return a.next < b.next }

	pub const wasi_batch_capacity = 1024

	pub struct WasiBatch {
	pub mut:
		array [wasi_batch_capacity]WasiSubscription
		len   uint = 1
	}

	pub fn (mut self WasiBatch) get(c_ &WasiCompletion) !&WasiSubscription {
		if self.len >= uint(self.array.len) { return new_error(.batch_full) }
		mut c := unsafe { c_ }
		c.batch_idx = self.len
		self.len += 1
		return unsafe { &self.array[int(c.batch_idx)] }
	}

	pub fn (mut self WasiBatch) put(c_ &WasiCompletion) {
		mut c := unsafe { c_ }
		assert c.batch_idx > 0
		assert self.len > 1
		old_idx := c.batch_idx
		c.batch_idx = 0
		self.len -= 1
		// This is deliberately len == 0, as in the pinned source. The reserved
		// timeout slot means its last-user-slot case still performs the swap.
		if self.len == 0 { return }
		self.array[int(old_idx)] = self.array[int(self.len)]
		mut swapped := unsafe { &WasiCompletion(voidptr(uint(self.array[int(old_idx)].userdata))) }
		swapped.batch_idx = old_idx
	}

	@[heap]
	pub struct WasiLoop {
	pub mut:
		active      uint
		submissions IntrusiveQueue[WasiCompletion]
		asyncs      IntrusiveQueue[WasiCompletion]
		batch       WasiBatch
		timers      IntrusiveHeap[WasiHeapTimer] = IntrusiveHeap[WasiHeapTimer]{ less: wasi_timer_less }
		wakeup      u8
		cached_now  u64
		in_run      bool
		is_stopped  bool
	}

	pub fn WasiLoop.init(options Options) !WasiLoop {
		_ = options
		return WasiLoop{ cached_now: wasi_get_now()! }
	}

	pub fn (self &WasiLoop) deinit() { _ = self }

	pub fn (mut self WasiLoop) run(mode RunMode) ! {
		match mode {
			.no_wait { self.tick(0)! }
			.once { self.tick(1)! }
			.until_done {
				for !self.done() { self.tick(1)! }
			}
		}
	}

	pub fn (mut self WasiLoop) stop() { self.is_stopped = true }

	pub fn (self &WasiLoop) stopped() bool { return self.is_stopped }

	pub fn (mut self WasiLoop) add(c_ &WasiCompletion) {
		mut c := unsafe { c_ }
		c.flags.set_state(.adding)
		self.submissions.push(c)
	}

	pub fn (self &WasiLoop) done() bool {
		return self.is_stopped || (self.active == 0 && self.submissions.empty())
	}

	pub fn (mut self WasiLoop) async_notify(c_ &WasiCompletion) {
		mut c := unsafe { c_ }
		assert c.op is WasiAsyncWaitOp
		mut op := unsafe { &(c.op as WasiAsyncWaitOp) }
		$if wasm_threads ? {
			C.atomic_store_byte(&self.wakeup, 1)
			C.atomic_store_byte(&op.wakeup, 1)
		} $else {
			self.wakeup = 1
			op.wakeup = 1
		}
	}

	pub fn (mut self WasiLoop) tick(wait u32) ! {
		if self.is_stopped { return }
		if self.in_run { return new_error(.nested_runs_not_allowed) }
		self.in_run = true
		defer { self.in_run = false }
		mut queued := self.submissions
		self.submissions = IntrusiveQueue[WasiCompletion]{}
		for {
			mut c := queued.pop() or { break }
			if c.flags.state() != .adding { continue }
			self.start(c)
		}
		mut wait_rem := uint(wait)
		for {
			if self.is_stopped { return }
			self.update_now()
			if !(self.active > 0 && (wait == 0 || wait_rem > 0)) { break }
			for {
				t := self.timers.peek() or { break }
				if t.next >= self.cached_now { break }
				removed := self.timers.delete_min() or { panic('unreachable') }
				assert removed == t
				mut c := t.c
				c.flags.set_state(.dead)
				self.active -= 1
				if wait_rem > 0 { wait_rem -= 1 }
				if c.callback(c.userdata, self, c, WasiTimerResult{ timer: .expiration }) == .rearm {
					self.start(c)
				}
			}
			if !self.asyncs.empty() {
				wakeup := $if wasm_threads ? { C.atomic_load_byte(&self.wakeup) } $else { self.wakeup }
				if wakeup != 0 {
					$if wasm_threads ? {
						C.atomic_store_byte(&self.wakeup, 0)
					} $else {
						self.wakeup = 0
					}
					mut asyncs := self.asyncs
					self.asyncs = IntrusiveQueue[WasiCompletion]{}
					for {
						mut c := asyncs.pop() or { break }
						mut op := unsafe { &(c.op as WasiAsyncWaitOp) }
						c_wakeup := $if wasm_threads ? { C.atomic_load_byte(&op.wakeup) } $else { op.wakeup }
						if c_wakeup == 0 {
							self.asyncs.push(c)
							continue
						}
						c.flags.set_state(.dead)
						self.active -= 1
						if wait_rem > 0 { wait_rem -= 1 }
						if c.callback(c.userdata, self, c, WasiAsyncWaitResult{}) == .rearm {
							self.start(c)
						}
					}
				}
			}
			mut timeout := self.cached_now
			if wait_rem != 0 {
				timeout = if timer := self.timers.peek() {
					timer.next
				} else {
					self.cached_now + 60_000_000_000
				}
			}
			mut subscription := WasiSubscription{}
			subscription.u.tag = 0
			unsafe { subscription.u.u.clock = WasiSubscriptionClock{ id: 1, timeout: timeout, precision: 1_000_000, flags: 1 } }
			self.batch.array[0] = subscription
			mut events := [wasi_batch_capacity]WasiEvent{}
			assert uint(events.len) >= self.batch.len
			mut n := uint(0)
			$if wasm32_wasi {
				if C.__wasi_poll_oneoff(voidptr(&self.batch.array[0]), voidptr(&events[0]), self.batch.len, &n) != 0 {
					return new_error(.unexpected)
				}
			} $else {
				return new_error(.unexpected)
			}
			for event in events[..int(n)] {
				if event.userdata == 0 { continue }
				assert event.userdata <= u64(uint(-1))
				mut c := unsafe { &WasiCompletion(voidptr(uint(event.userdata))) }
				c.flags.set_state(.dead)
				self.batch.put(c)
				self.active -= 1
				result := c.perform()
				if c.callback(c.userdata, self, c, result) == .rearm { self.start(c) }
			}
			if wait == 0 { break }
			wait_rem = if wait_rem > n { wait_rem - n } else { 0 }
		}
	}

	fn (mut self WasiLoop) start(c_ &WasiCompletion) {
		mut c := unsafe { c_ }
		tag := c.op.tag()
		mut immediate := ?WasiResult(none)
		match mut c.op {
			WasiNoopOp {
				c.flags.set_state(.dead)
				return
			}
			WasiCancelOp {
				if c.flags.state() == .adding {
					if c.op.c.op is WasiCancelOp {
						immediate = WasiCancelResult{ err: .invalid_op }
					} else {
						self.stop_completion(c.op.c)
					}
				}
				if immediate == none { immediate = WasiCancelResult{} }
			}
			WasiReadOp, WasiPReadOp, WasiWriteOp, WasiPWriteOp, WasiRecvOp, WasiSendOp, WasiAcceptOp {
				sub := self.batch.get(c) or {
					immediate = wasi_result_kind(tag, error_kind(err))
					unsafe { &WasiSubscription(nil) }
				}
				if sub != unsafe { nil } {
					value := c.subscription()
					unsafe { *sub = value }
				}
			}
			WasiShutdownOp {
				how := match c.op.how {
					.both { u8(3) }
					.recv { u8(1) }
					.send { u8(2) }
				}
				immediate = $if wasm32_wasi {
					WasiShutdownResult{
						err: if C.__wasi_sock_shutdown(u32(c.op.socket), how) == 0 { none } else { ErrorKind.unexpected }
					}
				} $else {
					WasiShutdownResult{ err: .unexpected }
				}
			}
			WasiCloseOp {
				// std.posix.close deliberately ignores WASI fd_close's result.
				$if wasm32_wasi { _ = C.__wasi_fd_close(u32(c.op.fd)) }
				immediate = WasiCloseResult{}
			}
			WasiAsyncWaitOp { self.asyncs.push(c) }
			WasiHeapTimer {
				c.op.c = c
				self.timers.insert(&c.op)
			}
		}
		if result := immediate {
			c.flags.set_state(.dead)
			if c.callback(c.userdata, self, c, result) == .rearm { self.add(c) }
			return
		}
		c.flags.set_state(.active)
		self.active += 1
	}

	fn (mut self WasiLoop) stop_completion(c_ &WasiCompletion) {
		mut c := unsafe { c_ }
		active := c.flags.state() == .active
		mut rearm := false
		match mut c.op {
			WasiHeapTimer {
				assert c.op.c == c
				if active { self.timers.remove(&c.op) }
				if c.flags.state() != .dead {
					if reset := c.op.reset {
						c.op.next = reset
						c.op.reset = none
						rearm = true
					} else {
						c.flags.set_state(.dead)
						rearm = c.callback(c.userdata, self, c, WasiTimerResult{ timer: .cancel }) == .rearm
					}
				}
			}
			else { panic('unreachable') }
		}
		if active { self.active -= 1 }
		if rearm { self.start(c) }
	}

	pub fn (mut self WasiLoop) timer(c_ &WasiCompletion, next_ms u64, userdata voidptr, cb WasiCallback) {
		mut c := unsafe { c_ }
		unsafe { *c = WasiCompletion{ op: WasiHeapTimer{ next: wasi_timer_next(next_ms) }, userdata: userdata, callback: cb } }
		self.add(c)
	}

	pub fn (mut self WasiLoop) timer_reset(c_ &WasiCompletion, c_cancel_ &WasiCompletion, next_ms u64, userdata voidptr, cb WasiCallback) {
		mut c := unsafe { c_ }
		mut c_cancel := unsafe { c_cancel_ }
		match c.flags.state() {
			.dead, .deleting {
				self.timer(c, next_ms, userdata, cb)
				return
			}
			.adding {
				mut timer := unsafe { &(c.op as WasiHeapTimer) }
				timer.next = wasi_timer_next(next_ms)
				c.userdata = userdata
				c.callback = cb
				return
			}
			.active {
				mut timer := unsafe { &(c.op as WasiHeapTimer) }
				timer.reset = wasi_timer_next(next_ms)
				c.userdata = userdata
				c.callback = cb
				if c_cancel.state() == .active { return }
				assert c_cancel.state() == .dead && c.state() == .active
				unsafe { *c_cancel = WasiCompletion{ op: WasiCancelOp{ c: c } } }
				self.add(c_cancel)
			}
		}
	}

	pub fn (self &WasiLoop) now() i64 { return i64(self.cached_now / 1_000_000) }

	pub fn (mut self WasiLoop) update_now() {
		if timestamp := wasi_get_now() { self.cached_now = timestamp }
	}

	fn wasi_timer_next(next_ms u64) u64 {
		timestamp := wasi_get_now() or { panic('unreachable clock_time_get') }
		return timestamp + next_ms * 1_000_000
	}

	fn wasi_get_now() !u64 {
		$if wasm32_wasi {
			mut timestamp := u64(0)
			code := C.__wasi_clock_time_get(1, 1, &timestamp)
			if code == 0 { return timestamp }
			if code == 28 { return new_error(.unsupported_clock) }
			return new_error(.unexpected)
		} $else {
			return time.sys_mono_now()
		}
	}

	fn (self &WasiCompletion) subscription() WasiSubscription {
		mut result := WasiSubscription{ userdata: u64(uint(self)) }
		match self.op {
			WasiReadOp, WasiPReadOp, WasiRecvOp {
				result.u.tag = 1
				unsafe { result.u.u.fd_read = WasiSubscriptionFd{ fd: u32(self.op.fd) } }
			}
			WasiWriteOp, WasiPWriteOp, WasiSendOp {
				result.u.tag = 2
				unsafe { result.u.u.fd_write = WasiSubscriptionFd{ fd: u32(self.op.fd) } }
			}
			WasiAcceptOp {
				result.u.tag = 1
				unsafe { result.u.u.fd_read = WasiSubscriptionFd{ fd: u32(self.op.socket) } }
			}
			else { panic('unreachable') }
		}
		return result
	}

	// std.posix selects libc on this C backend. Its existing wrappers preserve
	// EINTR retries, bounded syscall sizes, and exact read/write errno maps.
	fn (mut self WasiCompletion) perform() WasiResult {
		tag := self.op.tag()
		match mut self.op {
			WasiReadOp {
				buf := self.op.buffer.slice_ptr()
				n := posix_read(self.op.fd, buf) or { return wasi_result_kind(tag, error_kind(err)) }
				if n == 0 { return wasi_result_kind(tag, .eof) }
				return wasi_result_n(tag, n)
			}
			WasiPReadOp {
				buf := self.op.buffer.slice_ptr()
				n := posix_pread(self.op.fd, buf, self.op.offset) or { return wasi_result_kind(tag, error_kind(err)) }
				if n == 0 { return wasi_result_kind(tag, .eof) }
				return wasi_result_n(tag, n)
			}
			WasiWriteOp {
				buf := self.op.buffer.bytes()
				n := posix_write(self.op.fd, buf) or { return wasi_result_kind(tag, error_kind(err)) }
				return wasi_result_n(tag, n)
			}
			WasiPWriteOp {
				buf := self.op.buffer.bytes()
				n := posix_pwrite(self.op.fd, buf, self.op.offset) or { return wasi_result_kind(tag, error_kind(err)) }
				return wasi_result_n(tag, n)
			}
			WasiRecvOp {
				$if wasm32_wasi {
					buf := self.op.buffer.slice_ptr()
					iov := WasiIovec{ base: buf.data, len: uint(buf.len) }
					mut n := uint(0)
					mut roflags := u16(0)
					if C.__wasi_sock_recv(u32(self.op.fd), voidptr(&iov), 1, 0, &n, &roflags) != 0 {
						return wasi_result_kind(.recv, .unexpected)
					}
					return wasi_result_n(.recv, n)
				} $else {
					return wasi_result_kind(.recv, .unexpected)
				}
			}
			WasiSendOp {
				$if wasm32_wasi {
					buf := self.op.buffer.bytes()
					iov := WasiIovec{ base: buf.data, len: uint(buf.len) }
					mut n := uint(0)
					if C.__wasi_sock_send(u32(self.op.fd), voidptr(&iov), 1, 0, &n) != 0 {
						return wasi_result_kind(.send, .unexpected)
					}
					return wasi_result_n(.send, n)
				} $else {
					return wasi_result_kind(.send, .unexpected)
				}
			}
			WasiAcceptOp {
				$if wasm32_wasi {
					mut fd := u32(0)
					if C.__wasi_sock_accept(u32(self.op.socket), 0, &fd) != 0 {
						return WasiAcceptResult{ err: .unexpected }
					}
					assert fd <= 0x7fffffff
					return WasiAcceptResult{ socket: int(fd) }
				} $else {
					return WasiAcceptResult{ err: .unexpected }
				}
			}
			else { panic('unreachable') }
		}
	}
}
