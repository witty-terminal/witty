module xev

$if macos || ios || freebsd {
	// Backend to use kqueue. This is currently only tested on macOS but
	// support for BSDs is planned (if it doesn't already work).
	//
	// V translation of libxev's src/backend/kqueue.zig (pinned 34fa508). Zig's
	// `Xev(.kqueue, kqueue)` API types carry a `Kqueue` prefix in this module.
	// The Operation and Result tagged unions are represented as flat records with
	// a tag so that the timer payload has a stable address inside a completion.

	#include <sys/event.h>

	$if macos || ios {
		pub struct C.kevent64_s {
		mut:
			ident  u64
			filter i16
			flags  u16
			fflags u32
			data   i64
			udata  u64
			ext    [2]u64
		}

		fn C.kevent64(kq int, changelist &C.kevent64_s, nchanges int, eventlist &C.kevent64_s, nevents int, flags u32, timeout &C.timespec) int

		pub type Kevent = C.kevent64_s
	} $else $if freebsd {
		// std.c.Kevent on FreeBSD has four extension words and pointer udata.
		pub struct C.kevent {
		mut:
			ident  uint
			filter i16
			flags  u16
			fflags u32
			data   i64
			udata  voidptr
			ext    [4]u64
		}

		fn C.kevent(kq int, changelist &C.kevent, nchanges int, eventlist &C.kevent, nevents int, timeout &C.timespec) int

		pub type Kevent = C.kevent
	}

	fn C.kqueue() int

	// The callback of the main Loop operations. Higher level interfaces may
	// use a different callback mechanism.
	pub type KqueueCallback = fn (userdata voidptr, loop &KqueueLoop, completion &KqueueCompletion, result KqueueResult) CallbackAction

	// A callback that does nothing and immediately disarms. This
	// implements xev.Callback and is the default value for completions.
	pub fn kqueue_noop_callback(_ voidptr, _ &KqueueLoop, _ &KqueueCompletion, _ KqueueResult) CallbackAction {
		return .disarm
	}

	// True if this backend is available on this platform.
	pub fn kqueue_available() bool {
		// macOS uses kqueue
		return true
	}

	pub const kqueue_note_exit_flags = $if macos || ios {
		u32(int(C.NOTE_EXIT)) | u32(int(C.NOTE_EXITSTATUS))
	} $else {
		u32(int(C.NOTE_EXIT))
	}

	// Some internal fields we can pack for better space.
	pub struct KqueueLoopFlags {
	pub mut:
		value u8
	}

	// True once it is initialized.
	pub fn (f KqueueLoopFlags) init() bool {
		return f.value & 0b001 != 0
	}

	// Whether we're in a run or not (to prevent nested runs).
	pub fn (f KqueueLoopFlags) in_run() bool {
		return f.value & 0b010 != 0
	}

	// Whether our loop is in a stopped state or not.
	pub fn (f KqueueLoopFlags) stopped() bool {
		return f.value & 0b100 != 0
	}

	fn (mut f KqueueLoopFlags) set(mask u8, v bool) {
		if v {
			f.value |= mask
		} else {
			f.value &= ~mask
		}
	}

	pub fn (mut f KqueueLoopFlags) set_init(v bool) {
		f.set(0b001, v)
	}

	pub fn (mut f KqueueLoopFlags) set_in_run(v bool) {
		f.set(0b010, v)
	}

	pub fn (mut f KqueueLoopFlags) set_stopped(v bool) {
		f.set(0b100, v)
	}

	@[heap]
	pub struct KqueueLoop {
	pub mut:
		// The fd of the kqueue.
		kqueue_fd int

		// The wakeup mechanism (mach ports on Apple, eventfd on BSD).
		wakeup_state KqueueWakeup

		// The number of active completions. This DOES NOT include completions that
		// are queued in the submissions queue.
		active uint

		// Our queue of submissions that we want to enqueue on the next tick.
		// These are NOT started, they are NOT submitted to kqueue. They are
		// pending.
		submissions IntrusiveQueue[KqueueCompletion]

		// The queue of cancellation requests. These will point to the
		// completion that we need to cancel. We don't queue the exact completion
		// to cancel because it may be in another queue.
		cancellations IntrusiveQueue[KqueueCompletion]

		// Our queue of completed completions where the callback hasn't been
		// called yet, but the "result" field should be set on every completion.
		// This is used to delay completion callbacks until the next tick.
		// Values in the completion queue must not be in the kqueue.
		completions IntrusiveQueue[KqueueCompletion]

		// Heap of timers. We use heaps instead of the EVFILT_TIMER because
		// it avoids a lot of syscalls in the case where there are a LOT of
		// timers.
		timers IntrusiveHeap[KqueueHeapTimer] = IntrusiveHeap[KqueueHeapTimer]{
			less: kqueue_timer_less
		}

		// The thread pool to use for blocking operations that kqueue can't do.
		thread_pool &ThreadPool = unsafe { nil }

		// The MPSC queue for completed completions from the thread pool.
		thread_pool_completions IntrusiveMpscQueue[KqueueCompletion]

		// Cached time
		cached_now Timespec

		// Some internal fields we can pack for better space.
		flags KqueueLoopFlags
	}

	// Initialize a new kqueue-backed event loop. See the Options docs
	// for what options matter for kqueue.
	pub fn KqueueLoop.init(options Options) !KqueueLoop {
		// This creates a new kqueue fd
		fd := posix_kqueue()!

		mut wakeup_state := KqueueWakeup.init() or {
			posix_close(fd)
			return err
		}

		mut res := KqueueLoop{
			kqueue_fd:    fd
			wakeup_state: wakeup_state
			thread_pool:  options.thread_pool
		}

		res.update_now()
		return res
	}

	// Deinitialize the loop, this closes the kqueue. Any events that
	// were unprocessed are lost -- their callbacks will never be called.
	pub fn (mut self KqueueLoop) deinit() {
		posix_close(self.kqueue_fd)
		self.wakeup_state.deinit()
	}

	// Stop the loop. This can only be called from the main thread.
	// This will stop the loop forever. Future ticks will do nothing.
	//
	// This does NOT stop any completions that are queued to be executed
	// in the thread pool. If you are using a thread pool, completions
	// are not safe to recover until the thread pool is shut down. If
	// you're not using a thread pool, all completions are safe to
	// read/write once any outstanding `run` or `tick` calls are returned.
	pub fn (mut self KqueueLoop) stop() {
		self.flags.set_stopped(true)
	}

	// Returns true if the loop is stopped. This may mean there
	// are still pending completions to be processed.
	pub fn (self &KqueueLoop) stopped() bool {
		return self.flags.stopped()
	}

	// Add a completion to the loop. The completion is not started until
	// the loop is run (`run`, `tick`) or an explicit submission request
	// is made (`submit`).
	pub fn (mut self KqueueLoop) add(completion &KqueueCompletion) {
		mut c := unsafe { completion }

		// If this is a cancellation, we special case it and add it to
		// a separate queue so we can handle them first.
		if c.op is KqueueCancelOp {
			mut unused := Kevent{}
			assert !self.start(mut c, mut unused)
			return
		}

		// We just add the completion to the queue. Failures can happen
		// at submission or tick time.
		c.flags.set_state(.adding)
		self.submissions.push(c)
	}

	// Submit any enqueue completions. This does not fire any callbacks
	// for completed events (success or error). Callbacks are only fired
	// on the next tick.
	//
	// If an error is returned, some events might be lost. Errors are
	// exceptional and should generally not happen. If we could recover
	// which completions were not submitted and restore them we would,
	// but the kqueue API doesn't provide that level of clarity.
	pub fn (mut self KqueueLoop) submit() ! {
		// We try to submit as many events at once as we can.
		mut events := [256]Kevent{}
		mut events_len := 0

		// Submit all the submissions. We copy the submission queue so that
		// any resubmits don't cause an infinite loop.
		mut queued := self.submissions
		self.submissions = IntrusiveQueue[KqueueCompletion]{}

		for {
			queue_pop: for {
				mut c := queued.pop() or { break }
				match c.flags.state() {
					// If we're adding then we start the event.
					.adding {
						if self.start(mut c, mut events[events_len]) {
							events_len += 1
							if events_len >= events.len {
								break queue_pop
							}
						}
					}
					// If we're deleting then we create a deletion event and
					// queue the completion to notify cancellation.
					.deleting {
						if ev := c.kevent() {
							ecanceled := -1 * i32(C.ECANCELED)
							c.result = c.syscall_result(ecanceled)
							c.flags.set_state(.dead)
							self.completions.push(c)

							events[events_len] = ev
							events[events_len].flags = u16(int(C.EV_DELETE))
							events_len += 1
							if events_len >= events.len {
								break queue_pop
							}
						}
					}
					// This is set if the completion was canceled while in the
					// submission queue. This is a special case where we still
					// want to call the callback to tell it it was canceled.
					.dead {
						self.stop_completion(mut c)
					}
					// Shouldn't happen if our logic is all correct.
					.active {
						eprintln('libxev_kqueue: invalid state in submission queue state=${c.flags.state()}')
					}
				}
			}

			// If we have no events then we have to have gone through the entire
			// submission queue and we're done.
			if events_len == 0 {
				break
			}

			// Zero timeout so that kevent returns immediately.
			mut timeout := Timespec{}
			completed := kevent_syscall(self.kqueue_fd, &events[0], uint(events_len), &events[0],
				uint(events.len), &timeout) or {
				// On error, we have to restore the queue because we may be batching.
				self.submissions = queued
				return err
			}
			events_len = 0

			// Go through the completed events and queue them.
			// NOTE: we currently never process completions (we set
			// event list to zero length) because it was leading to
			// memory corruption we need to investigate.
			for i in 0 .. completed {
				ev := events[i]

				// Zero udata values are internal events that we do nothing
				// on such as the mach port wakeup.
				if ev.udata == 0 {
					continue
				}

				// We handle deletions separately.
				if ev.flags & u16(C.EV_DELETE) != 0 {
					continue
				}

				mut c := unsafe { &KqueueCompletion(voidptr(uint(ev.udata))) }

				// If EV_ERROR is set, then submission failed for this
				// completion. We get the syscall errorcode from data and
				// store it.
				if ev.flags & u16(C.EV_ERROR) != 0 {
					c.result = c.syscall_result(-i32(ev.data))
				} else {
					// No error, means that this completion is ready to work.
					c.result = c.perform(&ev)
				}

				assert c.result != none
				self.completions.push(c)
			}
		}
	}

	// Process the cancellations queue. This doesn't call any callbacks
	// or perform any syscalls. This just shuffles state around and sets
	// things up for cancellation to occur.
	fn (mut self KqueueLoop) process_cancellations() {
		for {
			mut c := self.cancellations.pop() or { break }
			mut target := (c.op as KqueueCancelOp).c
			match target.flags.state() {
				// If the target is dead already we do nothing.
				.dead {}
				// If the targeting is in the process of being removed
				// from the kqueue we do nothing because its already done.
				.deleting {}
				// If they are in the submission queue, mark them as dead
				// so they will never be submitted.
				.adding {
					target.flags.set_state(.dead)
				}
				// If it is active we need to schedule the deletion.
				.active {
					self.stop_completion(mut target)
				}
			}

			// We completed the cancellation.
			c.result = KqueueCancelResult{}
			self.completions.push(c)
		}
	}

	// Run the event loop. See RunMode documentation for details on modes.
	// Once the loop is run, the pointer MUST remain stable.
	pub fn (mut self KqueueLoop) run(mode RunMode) ! {
		match mode {
			.no_wait {
				self.tick(0)!
			}
			.once {
				self.tick(1)!
			}
			.until_done {
				for !self.done() {
					self.tick(1)!
				}
			}
		}
	}

	// Tick through the event loop once, waiting for at least "wait" completions
	// to be processed by the loop itself.
	pub fn (mut self KqueueLoop) tick(wait u32) ! {
		// If we're stopped then the loop is fully over.
		if self.flags.stopped() {
			return
		}

		// We can't nest runs.
		if self.flags.in_run() {
			return new_error(.nested_runs_not_allowed)
		}
		self.flags.set_in_run(true)
		defer {
			self.flags.set_in_run(false)
		}

		// Initialize
		if !self.flags.init() {
			self.flags.set_init(true)

			if !isnil(self.thread_pool) {
				self.thread_pool_completions.init()
			}

			self.wakeup_state.setup(self.kqueue_fd) or {
				// We reset initialization because we can't do anything
				// safely unless we get this mach port registered!
				self.flags.set_init(false)
				return err
			}
		}

		// The list of events, used as both a changelist and eventlist.
		mut events := [256]Kevent{}

		// The number of events in the events array to submit as changes
		// on repeat ticks. Used mostly for efficient disarm.
		mut changes := 0

		mut wait_rem := uint(wait)

		// Handle all of our cancellations first because we may be able
		// to stop submissions from even happening if its still queued.
		// Plus, cancellations sometimes add more to the submission queue
		// (to remove from kqueue)
		self.process_cancellations()

		// TODO(mitchellh): an optimization in the future is for the last
		// batch of submissions to return the changelist, because we can
		// reuse that for the kevent call later...
		self.submit()!

		// Explaining the loop condition: we want to loop only if we have
		// active handles (because it means we have something to do)
		// and we have stuff we want to wait for still (wait_rem > 0) or
		// we requested just a nowait tick (because we have to loop at least
		// once).
		//
		// We also loop if there are any requested changes. Requested
		// changes are only ever deletions currently, so we just process
		// those until we have no more.
		for {
			// If we're stopped then the loop is fully over.
			if self.flags.stopped() {
				return
			}

			// We must update our time no matter what
			self.update_now()

			// NOTE(mitchellh): This is a hideous boolean statement we should
			// clean it up.
			if !((self.active > 0 && (wait == 0 || wait_rem > 0)) || changes > 0
				|| !self.completions.empty()) {
				break
			}

			// Run our expired timers
			now_timer := KqueueHeapTimer{
				next: self.cached_now
			}
			for {
				mut t := self.timers.peek() or { break }
				if !kqueue_timer_less(t, &now_timer) {
					break
				}

				// Remove the timer
				deleted := self.timers.delete_min() or { panic('unreachable') }
				assert deleted == t

				// Mark completion as done
				mut c := t.c
				c.flags.set_state(.dead)

				// We mark it as inactive here because if we rearm below
				// the start() function will reincrement this.
				self.active -= 1

				// Lower our remaining count since we have processed something.
				wait_rem = sat_sub(wait_rem, 1)

				// Invoke
				action := c.callback(c.userdata, self, c, KqueueTimerResult{
					timer: .expiration
				})
				match action {
					.disarm {}
					// We use undefined as the second param because timers
					// never set a kevent, and we assert false for the same
					// reason.
					.rearm {
						mut unused := Kevent{}
						assert !self.start(mut c, mut unused)
					}
				}
			}

			// Migrate our completions from the thread pool MPSC queue to our
			// completion queue.
			// TODO: unify the queues
			if !isnil(self.thread_pool) {
				for {
					c := self.thread_pool_completions.pop() or { break }
					self.completions.push(c)
				}
			}

			// Process the completions we already have completed.
			for {
				mut c := self.completions.pop() or { break }

				// disarm_ev is the Kevent to use for disarming if the
				// completion wants to disarm. We have to calculate this up
				// front because c can be reused in callback.
				disarm_ev := if c.flags.state() != .active || c.flags.threadpool() {
					// If we're not active then we were never part of the kqueue.
					// If we are part of a threadpool we also never were part
					// of the kqueue.
					?Kevent(none)
				} else {
					c.kevent()
				}

				// We store whether this completion was active so we can decrement
				// the active count later
				c_active := c.flags.state() == .active
				c.flags.set_state(.dead)

				// Decrease our waiters because we are definitely processing one.
				wait_rem = sat_sub(wait_rem, 1)

				// Completion queue items MUST have a result set.
				result := c.result or { panic('unreachable') }
				action := c.callback(c.userdata, self, c, result)
				match action {
					// If we're active we have to schedule a delete. Otherwise
					// we do nothing because we were never part of the kqueue.
					.disarm {
						if ev := disarm_ev {
							events[changes] = ev
							events[changes].flags = u16(int(C.EV_DELETE))
							kevent_clear_userdata(mut events[changes])
							changes += 1
							assert changes <= events.len
						}

						if c_active {
							self.active -= 1
						}
					}
					// Only resubmit if we aren't already active (in the queue)
					.rearm {
						if !c_active {
							self.submissions.push(c)
						}
					}
				}

				// If we filled the events slice, we break to avoid overflow.
				if changes == events.len {
					break
				}
			}

			// Determine our next timeout based on the timers
			mut timeout_value := Timespec{}
			mut has_timeout := true
			if wait_rem == 0 {
				timeout_value = Timespec{}
			} else if t := self.timers.peek() {
				// If we have a timer, we want to set the timeout to our next
				// timer value. If we have no timer, we wait forever.

				// Determine the time in milliseconds.
				ms_now := u64(self.cached_now.tv_sec) * 1000 +
					u64(self.cached_now.tv_nsec) / 1_000_000
				ms_next := u64(t.next.tv_sec) * 1000 + u64(t.next.tv_nsec) / 1_000_000
				ms := sat_sub_u64(ms_next, ms_now)

				// Convert to s/ns for the timespec
				sec := ms / 1000
				nsec := (ms % 1000) * 1_000_000
				timeout_value = Timespec{
					tv_sec:  i64(sec)
					tv_nsec: i64(nsec)
				}
			} else {
				has_timeout = false
			}

			// Wait for changes. Note that we ALWAYS attempt to get completions
			// back even if are done waiting (wait_rem == 0) because if we have
			// to make a syscall to submit changes, we might as well also check
			// for done events too.
			mut timeout := unsafe { &Timespec(nil) }
			if has_timeout {
				timeout = &timeout_value
			}
			completed := kevent_syscall(self.kqueue_fd, &events[0], uint(changes), &events[0],
				uint(events.len), timeout) or {
				match error_kind(err) {
					// This should never happen because we always have
					// space in our event list. If I'm reading the BSD source
					// right (and Apple does something similar...) then ENOENT
					// is always put into the eventlist if there is space:
					// https://github.com/freebsd/freebsd-src/blob/5a4a83fd0e67a0d7787d2f3e09ef0e5552a1ffb6/sys/kern/kern_event.c#L1668
					.event_not_found {
						panic('unreachable')
					}
					// Any other error is fatal
					else {
						return err
					}
				}
			}

			// Reset changes since they're not submitted
			changes = 0

			// Go through the completed events and queue them.
			for i in 0 .. completed {
				ev := events[i]

				// Zero udata values are internal events that we do nothing
				// on such as the mach port wakeup.
				if ev.udata == 0 {
					continue
				}

				// Ignore any successful deletions. This can only happen
				// from disarms below and in that case we already processed
				// their callback.
				if ev.flags & u16(C.EV_DELETE) != 0 {
					continue
				}

				// This can only be set during changelist processing so
				// that means that this event was never actually active.
				// Therefore, we only decrement the waiters by 1 if we
				// processed an active change.
				if ev.flags & u16(C.EV_ERROR) != 0 {
					// We cannot use c here because c is already dead
					// at this point for this event.
					continue
				}
				wait_rem = sat_sub(wait_rem, 1)

				mut c := unsafe { &KqueueCompletion(voidptr(uint(ev.udata))) }

				// c is ready to be reused rigt away if we're dearming
				// so we mark it as dead.
				c.flags.set_state(.dead)

				result := c.perform(&ev)
				action := c.callback(c.userdata, self, c, result)
				match action {
					.disarm {
						// Mark this event for deletion, it'll happen
						// on the next tick.
						events[changes] = ev
						events[changes].flags = u16(int(C.EV_DELETE))
						kevent_clear_userdata(mut events[changes])
						changes += 1
						assert changes <= events.len

						self.active -= 1
					}
					// We rearm by default with kqueue so we just have to make
					// sure that the state is correct.
					.rearm {
						c.flags.set_state(.active)
					}
				}
			}

			// If we ran through the loop once we break if we don't care.
			if wait == 0 {
				break
			}
		}
	}

	// Returns the "loop" time in milliseconds. The loop time is updated
	// once per loop tick, before IO polling occurs. It remains constant
	// throughout callback execution.
	//
	// You can force an update of the "now" value by calling update_now()
	// at any time from the main thread.
	//
	// The clock that is used is not guaranteed. In general, a monotonic
	// clock source is always used if available. This value should typically
	// just be used for relative time calculations within the loop, such as
	// answering the question "did this happen <x> ms ago?".
	pub fn (self &KqueueLoop) now() i64 {
		// If anything overflows we just return the max value.
		max := max_i64

		// Calculate all the values, being careful about overflows in order
		// to just return the maximum value.
		sec := mul_i64(self.cached_now.tv_sec, 1000) or { return max }
		nsec := floor_div_i64(self.cached_now.tv_nsec, 1_000_000)
		return sat_add_i64(sec, nsec)
	}

	// Update the cached time.
	pub fn (mut self KqueueLoop) update_now() {
		if new_time := posix_clock_gettime(C.CLOCK_MONOTONIC) {
			self.cached_now = new_time
		} else {
			// Errors are ignored.
		}
	}

	// Add a timer to the loop. The timer will execute in "next_ms". This
	// is oneshot: the timer will not repeat. To repeat a timer, either
	// schedule another in your callback or return rearm from the callback.
	pub fn (mut self KqueueLoop) timer(c &KqueueCompletion, next_ms u64, userdata voidptr, cb KqueueCallback) {
		mut completion := unsafe { c }
		unsafe {
			*completion = KqueueCompletion{
				op:       KqueueHeapTimer{
					next: self.timer_next(next_ms)
				}
				userdata: userdata
				callback: cb
			}
		}
		self.add(completion)
	}

	// See io_uring.timer_reset for docs.
	pub fn (mut self KqueueLoop) timer_reset(c &KqueueCompletion, c_cancel &KqueueCompletion, next_ms u64, userdata voidptr, cb KqueueCallback) {
		mut completion := unsafe { c }
		mut cancel := unsafe { c_cancel }
		match completion.flags.state() {
			.dead, .deleting {
				self.timer(completion, next_ms, userdata, cb)
				return
			}
			// Adding state we can just modify the metadata and return
			// since the timer isn't in the heap yet.
			.adding {
				if mut completion.op is KqueueHeapTimer {
					completion.op.next = self.timer_next(next_ms)
				} else {
					panic('timer_reset: completion is not a timer')
				}
				completion.userdata = userdata
				completion.callback = cb
				return
			}
			.active {
				// Update the reset time for the timer to the desired time
				// along with all the callbacks.
				if mut completion.op is KqueueHeapTimer {
					completion.op.reset = self.timer_next(next_ms)
				} else {
					panic('timer_reset: completion is not a timer')
				}
				completion.userdata = userdata
				completion.callback = cb

				// If the cancellation is active, we assume its for this timer
				// and do nothing.
				if cancel.state() == .active {
					return
				}
				assert cancel.state() == .dead && completion.state() == .active
				unsafe {
					*cancel = KqueueCompletion{
						op: KqueueCancelOp{
							c: completion
						}
					}
				}
				self.add(cancel)
			}
		}
	}

	fn (self &KqueueLoop) timer_next(next_ms u64) Timespec {
		// Get the timestamp of the absolute time that we'll execute this timer.
		// There are lots of failure scenarios here in math. If we see any
		// of them we just use the maximum value.
		max := Timespec{
			tv_sec:  max_i64
			tv_nsec: max_i64
		}

		next_s := cast_i64(next_ms / 1000) or { return max }
		next_ns := cast_i64((next_ms % 1000) * 1_000_000) or { return max }

		return Timespec{
			tv_sec:  add_i64(self.cached_now.tv_sec, next_s) or { return max }
			tv_nsec: add_i64(self.cached_now.tv_nsec, next_ns) or { return max }
		}
	}

	fn (self &KqueueLoop) done() bool {
		return self.flags.stopped() || (self.active == 0 && self.submissions.empty()
			&& self.completions.empty())
	}

	struct KqueueStartKevent {}

	struct KqueueStartTimer {}

	struct KqueueStartCancel {}

	struct KqueueStartThreadpool {}

	struct KqueueStartResult {
		value i32
	}

	type KqueueStartAction = KqueueStartKevent
	| KqueueStartTimer
	| KqueueStartCancel
	| KqueueStartThreadpool
	| KqueueStartResult

	// Start the completion. This returns true if the Kevent was set
	// and should be queued.
	fn (mut self KqueueLoop) start(mut c KqueueCompletion, mut ev Kevent) bool {
		action := if c.flags.threadpool() {
			KqueueStartAction(KqueueStartThreadpool{})
		} else {
			match mut c.op {
				KqueueNoopOp {
					c.flags.set_state(.dead)
					return false
				}
				KqueueCancelOp {
					// Queue the cancel
					KqueueStartAction(KqueueStartCancel{})
				}
				KqueueAcceptOp {
					ev = c.kevent() or { panic('unreachable') }
					KqueueStartAction(KqueueStartKevent{})
				}
				KqueueConnectOp {
					mut connect_action := KqueueStartAction(KqueueStartResult{})
					for {
						rc := C.connect(c.op.socket, c.op.addr.any(), c.op.addr.get_os_sock_len())
						match posix_errno(rc) {
							// Interrupt, try again
							C.EINTR {
								continue
							}
							// This means the connect is blocked and in progress.
							// We register for the write event which will let us know
							// when it is complete.
							C.EAGAIN, C.EINPROGRESS {
								ev = c.kevent() or { panic('unreachable') }
								connect_action = KqueueStartKevent{}
								break
							}
							// Any other error we report. Like the source, this passes
							// the libc return code rather than a negated errno.
							else {
								connect_action = KqueueStartResult{
									value: i32(rc)
								}
								break
							}
						}
					}
					connect_action
				}
				KqueueWriteOp, KqueuePWriteOp, KqueueReadOp, KqueuePReadOp, KqueueSendOp,
				KqueueRecvOp, KqueueSendToOp, KqueueRecvFromOp, KqueueMachPortOp, KqueueProcOp {
					ev = c.kevent() or { panic('unreachable') }
					KqueueStartAction(KqueueStartKevent{})
				}
				KqueueShutdownOp {
					how := match c.op.how {
						.recv { C.SHUT_RD }
						.send { C.SHUT_WR }
						.both { C.SHUT_RDWR }
					}

					// Like the source, the libc return code is the result.
					KqueueStartAction(KqueueStartResult{
						value: i32(C.shutdown(c.op.socket, how))
					})
				}
				KqueueCloseOp {
					posix_close(c.op.fd)
					KqueueStartAction(KqueueStartResult{
						value: 0
					})
				}
				KqueueHeapTimer {
					// Point back to completion since we need this. In the future
					// we want to use @fieldParentPtr but https://github.com/ziglang/zig/issues/6611
					c.op.c = unsafe { &c }

					// Insert the timer into our heap.
					self.timers.insert(&c.op)

					// We always run timers
					KqueueStartAction(KqueueStartTimer{})
				}
			}
		}

		match action {
			KqueueStartKevent, KqueueStartTimer {
				// Increase our active count so we now wait for this. We
				// assume it'll successfully queue. If it doesn't we handle
				// that later (see submit)
				self.active += 1
				c.flags.set_state(.active)

				// We only return true if this is a kevent, since other
				// actions can come in here.
				return action is KqueueStartKevent
			}
			KqueueStartCancel {
				// We are considered an active completion.
				self.active += 1
				c.flags.set_state(.active)

				self.cancellations.push(c)
				return false
			}
			KqueueStartThreadpool {
				// We need to mark this completion as active no matter
				// what happens below so that we mark is inactive with
				// completion handling.
				self.active += 1
				c.flags.set_state(.active)

				// We need a thread pool otherwise we set an error on
				// our result and queue the completion.
				if isnil(self.thread_pool) {
					// We use EPERM as a way to note there is no thread
					// pool. We can change this in the future if there is
					// a better choice.
					eperm := -1 * i32(C.EPERM)
					c.result = c.syscall_result(eperm)
					self.completions.push(c)
					return false
				}
				mut pool := self.thread_pool

				// Setup our completion state so that the thread can
				// communicate back to our main thread.
				c.task_loop = unsafe { self }
				c.task = ThreadPoolTask{
					callback: kqueue_thread_perform
				}

				// Schedule it, from this point forward its not safe to touch c.
				pool.schedule(ThreadPoolBatch.from(&c.task))

				return false
			}
			// A result is immediately available. Queue the completion to
			// be invoked.
			KqueueStartResult {
				c.result = c.syscall_result(action.value)
				self.completions.push(c)

				return false
			}
		}
	}

	fn (mut self KqueueLoop) stop_completion(mut c KqueueCompletion) {
		if c.flags.state() == .active {
			// If there is a result already, then we're already in the
			// completion queue and we can be done. Items in the completion
			// queue can NOT be in the kqueue too.
			if c.result != none {
				return
			}

			// If this completion has a kevent associated with it, then
			// we must remove the kevent. We remove the kevent by adding it
			// to the submission queue (because its the same syscall) but
			// setting the state to deleting.
			if _ := c.kevent() {
				self.active -= 1
				c.flags.set_state(.deleting)
				self.submissions.push(c)
				return
			}
		}

		// Inspect other operations. WARNING: the state can be ANYTHING
		// here so per op be sure to check the state flag.
		match mut c.op {
			KqueueHeapTimer {
				if c.flags.state() == .active {
					// Remove from the heap so it never fires...
					self.timers.remove(&c.op)

					// If we have reset set AND we got a cancellation result,
					// that means that we were canceled so that we can update
					// our expiration time.
					if r := c.op.reset {
						c.op.next = r
						c.op.reset = none
						self.active -= 1
						self.add(c)
						return
					}
				}

				// Add to our completions so we trigger the callback.
				c.result = KqueueTimerResult{
					timer: .cancel
				}
				self.completions.push(c)

				// Note the timers state purposely remains ACTIVE so that
				// when we process the completion we decrement the
				// active count.
			}
			else {}
		}
	}

	// This is the main callback for the threadpool to perform work
	// on completions for the loop.
	fn kqueue_thread_perform(t &ThreadPoolTask) {
		mut c := unsafe { &KqueueCompletion(voidptr(uint(t) - __offsetof(KqueueCompletion, task))) }

		// Do our task
		c.result = c.perform(unsafe { nil })

		// Add to our completion queue
		mut loop := c.task_loop
		loop.thread_pool_completions.push(c)

		// The original thread_perform only wakes macOS, despite Darwin wakeup
		// storage also existing on iOS. Preserve that source platform guard.
		$if macos {
			loop.wakeup() or {}
		}
	}

	// Sends an empty message to this loop's mach port so that it wakes
	// up if it is blocking on kevent().
	fn (mut self KqueueLoop) wakeup() ! {
		self.wakeup_state.wakeup()!
	}

	// Watch state of this completion. We use this to determine whether
	// we're active, adding, deleting, etc. This lets us add and delete
	// multiple times before a loop tick and handle the state properly.
	pub enum KqueueCompletionStateFlag as u8 {
		// completion is not part of any loop
		dead = 0
		// completion is in the submission queue
		adding = 1
		// completion is in the deletion queue
		deleting = 2
		// completion is submitted with kqueue successfully
		active = 3
	}

	pub struct KqueueCompletionFlags {
	pub mut:
		value u8
	}

	// Watch state of this completion.
	pub fn (f KqueueCompletionFlags) state() KqueueCompletionStateFlag {
		return unsafe { KqueueCompletionStateFlag(f.value & 0b111) }
	}

	pub fn (mut f KqueueCompletionFlags) set_state(state KqueueCompletionStateFlag) {
		f.value = (f.value & ~u8(0b111)) | u8(state)
	}

	// Set this to true to schedule this operation on the thread pool.
	// This can be set by anyone. If the operation is scheduled on
	// the thread pool then it will NOT be registered with kqueue even
	// if it is supported.
	pub fn (f KqueueCompletionFlags) threadpool() bool {
		return f.value & 0b1000 != 0
	}

	pub fn (mut f KqueueCompletionFlags) set_threadpool(v bool) {
		if v {
			f.value |= 0b1000
		} else {
			f.value &= ~u8(0b1000)
		}
	}

	// A completion is a request to perform some work with the loop.
	@[heap]
	pub struct KqueueCompletion {
	pub mut:
		// Operation to execute.
		op KqueueOperation = KqueueNoopOp{}

		// Userdata and callback for when the completion is finished.
		userdata voidptr        = unsafe { nil }
		callback KqueueCallback = kqueue_noop_callback

		//---------------------------------------------------------------
		// Internal fields
		// Intrusive queue field
		next &KqueueCompletion = unsafe { nil }

		// Result code of the syscall. Only used internally in certain
		// scenarios, should not be relied upon by program authors.
		result ?KqueueResult

		flags KqueueCompletionFlags

		// If scheduled on a thread pool, this will be set. This is NOT a
		// reliable way to get access to the loop and shouldn't be used
		// except internally.
		task      ThreadPoolTask
		task_loop &KqueueLoop = unsafe { nil }
	}

	// Returns the state of this completion. There are some things to
	// be caution about when calling this function.
	//
	// First, this is only safe to call from the main thread. This cannot
	// be called from any other thread.
	//
	// Second, if you are using default "undefined" completions, this will
	// NOT return a valid value if you access it. You must zero your
	// completion using ".{}". You only need to zero the completion once.
	// Once the completion is in use, it will always be valid.
	//
	// Third, if you stop the loop (loop.stop()), the completions registered
	// with the loop will NOT be reset to a dead state.
	pub fn (self &KqueueCompletion) state() CompletionState {
		return match self.flags.state() {
			.dead { .dead }
			.adding, .deleting, .active { .active }
		}
	}

	// Returns a kevent for this completion, if any. Note that the
	// kevent isn't immediately useful for all event types. For example,
	// "connect" requires you to initiate the connection first.
	fn (self &KqueueCompletion) kevent() ?Kevent {
		udata := u64(uint(voidptr(self)))
		match self.op {
			KqueueNoopOp {
				panic('unreachable')
			}
			KqueueCancelOp, KqueueCloseOp, KqueueHeapTimer, KqueueShutdownOp {
				return none
			}
			KqueueAcceptOp {
				return kevent_init(u64(self.op.socket), i16(C.EVFILT_READ),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueConnectOp {
				return kevent_init(u64(self.op.socket), i16(C.EVFILT_WRITE),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueMachPortOp {
				$if macos {
					// The kevent below waits for a machport to have a message
					// available AND automatically reads the message into the
					// buffer since MACH_RCV_MSG is set.
					slice := self.op.buffer.slice_ptr()
					return Kevent{
						ident:  u64(self.op.port)
						filter: i16(C.EVFILT_MACHPORT)
						flags:  u16(C.EV_ADD | C.EV_ENABLE)
						fflags: mach_rcv_msg
						data:   0
						udata:  udata
						ext:    [u64(uint(slice.data)), u64(slice.len)]!
					}
				} $else {
					// The pinned source returns null outside macOS, including iOS.
					return none
				}
			}
			KqueueProcOp {
				return kevent_init(u64(self.op.pid), i16(C.EVFILT_PROC),
					u16(C.EV_ADD | C.EV_ENABLE), self.op.flags, udata)
			}
			KqueueWriteOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_WRITE),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueuePWriteOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_WRITE),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueSendOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_WRITE),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueSendToOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_WRITE),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueReadOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_READ),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueuePReadOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_READ),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueRecvOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_READ),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
			KqueueRecvFromOp {
				return kevent_init(u64(self.op.fd), i16(C.EVFILT_READ),
					u16(C.EV_ADD | C.EV_ENABLE), 0, udata)
			}
		}
	}

	// Perform the operation associated with this completion. This will
	// perform the full blocking operation for the completion.
	fn (mut self KqueueCompletion) perform(ev_ &Kevent) KqueueResult {
		op_tag := self.op.tag()
		match mut self.op {
			KqueueCancelOp, KqueueNoopOp, KqueueHeapTimer, KqueueShutdownOp {
				eprintln('libxev_kqueue: perform op=${op_tag}')
				panic('unreachable')
			}
			KqueueAcceptOp {
				v := posix_accept(self.op.socket, &self.op.addr, &self.op.addr_size, self.op.flags) or {
					return kqueue_result_err(.accept, err)
				}
				return KqueueAcceptResult{
					socket: v
				}
			}
			KqueueConnectOp {
				posix_getsockopt_error(self.op.socket) or {
					return kqueue_result_err(.connect, err)
				}
				return KqueueConnectResult{}
			}
			KqueueWriteOp {
				n := posix_write(self.op.fd, self.op.buffer.bytes()) or {
					return kqueue_result_err(.write, err)
				}
				return kqueue_result_n(.write, n)
			}
			KqueuePWriteOp {
				n := posix_pwrite(self.op.fd, self.op.buffer.bytes(), self.op.offset) or {
					return kqueue_result_err(.pwrite, err)
				}
				return kqueue_result_n(.pwrite, n)
			}
			KqueueSendOp {
				n := posix_send(self.op.fd, self.op.buffer.bytes(), 0) or {
					return kqueue_result_err(.send, err)
				}
				return kqueue_result_n(.send, n)
			}
			KqueueSendToOp {
				n := posix_sendto(self.op.fd, self.op.buffer.bytes(), 0, self.op.addr.any(),
					self.op.addr.get_os_sock_len()) or { return kqueue_result_err(.sendto, err) }
				return kqueue_result_n(.sendto, n)
			}
			KqueueReadOp {
				if self.op.buffer.is_empty_slice() {
					if isnil(ev_) {
						return kqueue_result_kind(.read, .missing_kevent)
					}
					return kqueue_read_result(.read, uint(ev_.data))
				}
				n := posix_read(self.op.fd, self.op.buffer.slice_ptr()) or {
					return kqueue_result_err(.read, err)
				}
				return kqueue_read_result(.read, n)
			}
			KqueuePReadOp {
				if self.op.buffer.is_empty_slice() {
					// The source reports the missing kevent through the `.read`
					// result field for every read-like operation.
					if isnil(ev_) {
						return kqueue_result_kind(.read, .missing_kevent)
					}
					return kqueue_read_result(.pread, uint(ev_.data))
				}
				n := posix_pread(self.op.fd, self.op.buffer.slice_ptr(), self.op.offset) or {
					return kqueue_result_err(.pread, err)
				}
				return kqueue_read_result(.pread, n)
			}
			KqueueRecvOp {
				if self.op.buffer.is_empty_slice() {
					if isnil(ev_) {
						return kqueue_result_kind(.read, .missing_kevent)
					}
					return kqueue_read_result(.recv, uint(ev_.data))
				}
				n := posix_recv(self.op.fd, self.op.buffer.slice_ptr(), 0) or {
					return kqueue_result_err(.recv, err)
				}
				return kqueue_read_result(.recv, n)
			}
			KqueueRecvFromOp {
				if self.op.buffer.is_empty_slice() {
					if isnil(ev_) {
						return kqueue_result_kind(.read, .missing_kevent)
					}
					return kqueue_read_result(.recvfrom, uint(ev_.data))
				}
				n := posix_recvfrom(self.op.fd, self.op.buffer.slice_ptr(), 0, &self.op.addr,
					&self.op.addr_size) or { return kqueue_result_err(.recvfrom, err) }
				return kqueue_read_result(.recvfrom, n)
			}
			// Our machport operation ALWAYS has MACH_RCV set so there
			// is no operation to perform. kqueue automatically reads in
			// the mach message into the read buffer.
			KqueueMachPortOp {
				return KqueueMachPortResult{}
			}
			// For proc watching, it is identical to the syscall result.
			KqueueProcOp {
				if isnil(ev_) {
					return kqueue_result_kind(.proc, .missing_kevent)
				}

				// If we have the exit status, we read it.
				if ev_.fflags & kqueue_note_exit_flags > 0 {
					data := u32(ev_.data)
					if wait_ifexited(data) {
						return KqueueProcResult{
							exit_code: wait_exitstatus(data)
						}
					}
				}

				return KqueueProcResult{}
			}
			KqueueCloseOp {
				posix_close(self.op.fd)
				return KqueueCloseResult{}
			}
		}
	}

	// Returns the error result for the given result code. This is called
	// in the situation that kqueue fails to enqueue the completion or
	// a raw syscall fails.
	fn (self &KqueueCompletion) syscall_result(r i32) KqueueResult {
		errno := if r >= 0 { 0 } else { int(-r) }
		tag := self.op.tag()
		match tag {
			.noop {
				panic('unreachable')
			}
			.accept {
				match errno {
					0 {
						return KqueueAcceptResult{
							socket: int(r)
						}
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.connect, .machport, .shutdown {
				match errno {
					0 {
						return kqueue_result_ok(tag)
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.write {
				match errno {
					0 {
						return kqueue_result_n(tag, uint(r))
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					C.EPERM {
						return kqueue_result_kind(tag, .permission_denied)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.pwrite, .send, .sendto, .recvfrom {
				match errno {
					0 {
						return kqueue_result_n(tag, uint(r))
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.read {
				match errno {
					0 {
						return kqueue_read_result(tag, uint(r))
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					C.EPERM {
						return kqueue_result_kind(tag, .permission_denied)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.pread, .recv {
				match errno {
					0 {
						return kqueue_read_result(tag, uint(r))
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.proc {
				match errno {
					0 {
						return KqueueProcResult{
							exit_code: u32(r)
						}
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					C.ESRCH {
						return kqueue_result_kind(tag, .no_such_process)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.close {
				match errno {
					0 {
						return kqueue_result_ok(tag)
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					C.EPERM {
						return kqueue_result_kind(tag, .thread_pool_required)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.timer {
				match errno {
					// Success is impossible because timers don't execute syscalls.
					0 {
						panic('unreachable')
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					else {
						return kqueue_result_err(tag, unexpected_errno(errno))
					}
				}
			}
			.cancel {
				match errno {
					0 {
						return kqueue_result_ok(tag)
					}
					C.ECANCELED {
						return kqueue_result_kind(tag, .canceled)
					}
					// Syscall errors should not be possible since cancel
					// doesn't run any syscalls.
					else {
						_ = unexpected_errno(errno)
						panic('unreachable')
					}
				}
			}
		}
	}

	// The result of an operation: the source's `Result` tagged union. Each
	// variant carries the operation's error union as the failing error name in
	// `err`, or its success payload.
	pub type KqueueResult = KqueueAcceptResult
	| KqueueCancelResult
	| KqueueCloseResult
	| KqueueConnectResult
	| KqueueMachPortResult
	| KqueueNoopResult
	| KqueuePReadResult
	| KqueuePWriteResult
	| KqueueProcResult
	| KqueueReadResult
	| KqueueRecvFromResult
	| KqueueRecvResult
	| KqueueSendResult
	| KqueueSendToResult
	| KqueueShutdownResult
	| KqueueTimerResult
	| KqueueWriteResult

	pub struct KqueueNoopResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct KqueueAcceptResult {
	pub mut:
		err    ?ErrorKind
		socket int
	}

	pub struct KqueueConnectResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct KqueueReadResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueueWriteResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueuePReadResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueuePWriteResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueueSendResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueueRecvResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueueSendToResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueueRecvFromResult {
	pub mut:
		err ?ErrorKind
		n   uint
	}

	pub struct KqueueCloseResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct KqueueShutdownResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct KqueueTimerResult {
	pub mut:
		err   ?ErrorKind
		timer KqueueTimerTrigger
	}

	pub struct KqueueCancelResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct KqueueMachPortResult {
	pub mut:
		err ?ErrorKind
	}

	pub struct KqueueProcResult {
	pub mut:
		err       ?ErrorKind
		exit_code u32
	}

	// The tag of the active result variant.
	pub fn (self KqueueResult) tag() KqueueOperationType {
		return match self {
			KqueueNoopResult { .noop }
			KqueueAcceptResult { .accept }
			KqueueConnectResult { .connect }
			KqueueReadResult { .read }
			KqueueWriteResult { .write }
			KqueuePReadResult { .pread }
			KqueuePWriteResult { .pwrite }
			KqueueSendResult { .send }
			KqueueRecvResult { .recv }
			KqueueSendToResult { .sendto }
			KqueueRecvFromResult { .recvfrom }
			KqueueCloseResult { .close }
			KqueueShutdownResult { .shutdown }
			KqueueTimerResult { .timer }
			KqueueCancelResult { .cancel }
			KqueueMachPortResult { .machport }
			KqueueProcResult { .proc }
		}
	}

	// kqueue_result_kind builds the `tag` result variant carrying an error.
	fn kqueue_result_kind(tag KqueueOperationType, kind ErrorKind) KqueueResult {
		match tag {
			.noop {
				return KqueueNoopResult{
					err: kind
				}
			}
			.accept {
				return KqueueAcceptResult{
					err: kind
				}
			}
			.connect {
				return KqueueConnectResult{
					err: kind
				}
			}
			.read {
				return KqueueReadResult{
					err: kind
				}
			}
			.write {
				return KqueueWriteResult{
					err: kind
				}
			}
			.pread {
				return KqueuePReadResult{
					err: kind
				}
			}
			.pwrite {
				return KqueuePWriteResult{
					err: kind
				}
			}
			.send {
				return KqueueSendResult{
					err: kind
				}
			}
			.recv {
				return KqueueRecvResult{
					err: kind
				}
			}
			.sendto {
				return KqueueSendToResult{
					err: kind
				}
			}
			.recvfrom {
				return KqueueRecvFromResult{
					err: kind
				}
			}
			.close {
				return KqueueCloseResult{
					err: kind
				}
			}
			.shutdown {
				return KqueueShutdownResult{
					err: kind
				}
			}
			.timer {
				return KqueueTimerResult{
					err: kind
				}
			}
			.cancel {
				return KqueueCancelResult{
					err: kind
				}
			}
			.machport {
				return KqueueMachPortResult{
					err: kind
				}
			}
			.proc {
				return KqueueProcResult{
					err: kind
				}
			}
		}
	}

	// kqueue_result_ok builds the successful `tag` variant of a void result.
	fn kqueue_result_ok(tag KqueueOperationType) KqueueResult {
		match tag {
			.connect {
				return KqueueConnectResult{}
			}
			.machport {
				return KqueueMachPortResult{}
			}
			.shutdown {
				return KqueueShutdownResult{}
			}
			.close {
				return KqueueCloseResult{}
			}
			.cancel {
				return KqueueCancelResult{}
			}
			else {
				panic('kqueue_result_ok: ${tag} carries a payload')
			}
		}
	}

	fn kqueue_result_err(tag KqueueOperationType, err IError) KqueueResult {
		return kqueue_result_kind(tag, error_kind(err))
	}

	// kqueue_result_n builds the byte-count result variant for `tag`.
	fn kqueue_result_n(tag KqueueOperationType, n uint) KqueueResult {
		match tag {
			.read {
				return KqueueReadResult{
					n: n
				}
			}
			.write {
				return KqueueWriteResult{
					n: n
				}
			}
			.pread {
				return KqueuePReadResult{
					n: n
				}
			}
			.pwrite {
				return KqueuePWriteResult{
					n: n
				}
			}
			.send {
				return KqueueSendResult{
					n: n
				}
			}
			.recv {
				return KqueueRecvResult{
					n: n
				}
			}
			.sendto {
				return KqueueSendToResult{
					n: n
				}
			}
			.recvfrom {
				return KqueueRecvFromResult{
					n: n
				}
			}
			else {
				panic('kqueue_result_n: ${tag} has no byte count')
			}
		}
	}

	// The zero-length read path returns EOF for a zero byte count.
	fn kqueue_read_result(tag KqueueOperationType, n uint) KqueueResult {
		if n == 0 {
			return kqueue_result_kind(tag, .eof)
		}
		return kqueue_result_n(tag, n)
	}

	// kqueue_result_bytes returns the byte count of a read or write result.
	fn kqueue_result_bytes(r KqueueResult) uint {
		return match r {
			KqueueReadResult { r.n }
			KqueueWriteResult { r.n }
			KqueuePReadResult { r.n }
			KqueuePWriteResult { r.n }
			KqueueSendResult { r.n }
			KqueueRecvResult { r.n }
			KqueueSendToResult { r.n }
			KqueueRecvFromResult { r.n }
			else { panic('kqueue_result_bytes: ${r.tag()} has no byte count') }
		}
	}

	// The struct used for loop wakeup. This is only internal state.
	$if macos || ios {
		pub struct KqueueWakeup {
		pub mut:
			// The mach port that this kqueue always has a filter for. Writing
			// an empty message to this port can be used to wake up the loop
			// at any time. Waking up the loop via this port won't trigger any
			// particular completion, it just forces tick to cycle.
			mach_port        KqueueAsync
			mach_port_buffer [32]u8
		}

		fn KqueueWakeup.init() !KqueueWakeup {
			mach_port := KqueueAsync.init()!
			return KqueueWakeup{
				mach_port: mach_port
			}
		}

		fn (mut self KqueueWakeup) deinit() {
			self.mach_port.deinit()
		}

		fn (mut self KqueueWakeup) setup(kqueue_fd int) ! {
			events := [
				Kevent{
					ident:  u64(self.mach_port.port)
					filter: i16(C.EVFILT_MACHPORT)
					flags:  u16(C.EV_ADD | C.EV_ENABLE)
					fflags: mach_rcv_msg
					data:   0
					udata:  0
					ext:    [u64(uint(&self.mach_port_buffer[0])), u64(self.mach_port_buffer.len)]!
				},
			]!
			n := kevent_syscall(kqueue_fd, &events[0], uint(events.len), &events[0], 0,
				unsafe { nil })!
			assert n == 0
		}

		fn (mut self KqueueWakeup) wakeup() ! {
			self.mach_port.notify()!
		}
	} $else $if freebsd {
		// Original backend/kqueue.zig Wakeup's non-Darwin branch. It explicitly
		// leaves these resource-free lifecycle methods empty and panics on wakeup;
		// no eventfd-based loop wakeup algorithm exists in the pinned original.
		pub struct KqueueWakeup {}

		fn KqueueWakeup.init() !KqueueWakeup {
			return KqueueWakeup{}
		}

		fn (mut self KqueueWakeup) deinit() {
			_ = self
		}

		fn (mut self KqueueWakeup) setup(kqueue_fd int) ! {
			_ = self
			_ = kqueue_fd
		}

		fn (mut self KqueueWakeup) wakeup() ! {
			_ = self
			panic('wakeup not implemented on this platform')
		}
	}

	pub enum KqueueOperationType as u8 {
		noop
		accept
		connect
		read
		write
		pread
		pwrite
		send
		recv
		sendto
		recvfrom
		close
		shutdown
		timer
		cancel
		machport
		proc
	}

	// All the supported operations of this event loop. These are always
	// backend-specific and therefore the structure and types change depending
	// on the underlying system in use. The high level operations are
	// done by initializing the request handles.
	pub type KqueueOperation = KqueueAcceptOp
	| KqueueCancelOp
	| KqueueCloseOp
	| KqueueConnectOp
	| KqueueHeapTimer
	| KqueueMachPortOp
	| KqueueNoopOp
	| KqueuePReadOp
	| KqueuePWriteOp
	| KqueueProcOp
	| KqueueReadOp
	| KqueueRecvFromOp
	| KqueueRecvOp
	| KqueueSendOp
	| KqueueSendToOp
	| KqueueShutdownOp
	| KqueueWriteOp

	// The tag of the active operation variant.
	pub fn (self KqueueOperation) tag() KqueueOperationType {
		return match self {
			KqueueNoopOp { .noop }
			KqueueAcceptOp { .accept }
			KqueueConnectOp { .connect }
			KqueueReadOp { .read }
			KqueueWriteOp { .write }
			KqueuePReadOp { .pread }
			KqueuePWriteOp { .pwrite }
			KqueueSendOp { .send }
			KqueueRecvOp { .recv }
			KqueueSendToOp { .sendto }
			KqueueRecvFromOp { .recvfrom }
			KqueueCloseOp { .close }
			KqueueShutdownOp { .shutdown }
			KqueueHeapTimer { .timer }
			KqueueCancelOp { .cancel }
			KqueueMachPortOp { .machport }
			KqueueProcOp { .proc }
		}
	}

	pub struct KqueueNoopOp {}

	pub struct KqueueAcceptOp {
	pub mut:
		socket    int
		addr      SockAddr
		addr_size u32 = u32(sizeof(SockAddr))
		flags     u32 = sock_cloexec
	}

	pub struct KqueueConnectOp {
	pub mut:
		socket int
		addr   NetAddress
	}

	pub struct KqueueReadOp {
	pub mut:
		fd     int
		buffer KqueueReadBuffer
	}

	pub struct KqueueWriteOp {
	pub mut:
		fd     int
		buffer KqueueWriteBuffer
	}

	pub struct KqueuePReadOp {
	pub mut:
		fd     int
		buffer KqueueReadBuffer
		offset u64
	}

	pub struct KqueueSendOp {
	pub mut:
		fd     int
		buffer KqueueWriteBuffer
	}

	pub struct KqueueRecvOp {
	pub mut:
		fd     int
		buffer KqueueReadBuffer
	}

	pub struct KqueuePWriteOp {
	pub mut:
		fd     int
		buffer KqueueWriteBuffer
		offset u64
	}

	// Note: this is making our Completion quite large. We can follow
	// the pattern of io_uring and require another user-provided pointer
	// here for state to move all this stuff out to a pointer.
	pub struct KqueueSendToOp {
	pub mut:
		fd     int
		buffer KqueueWriteBuffer
		addr   NetAddress
	}

	pub struct KqueueRecvFromOp {
	pub mut:
		fd        int
		buffer    KqueueReadBuffer
		addr      SockAddr
		addr_size u32 = u32(sizeof(SockAddr))
	}

	pub struct KqueueCloseOp {
	pub mut:
		fd int
	}

	pub struct KqueueShutdownOp {
	pub mut:
		socket int
		how    ShutdownHow = .both
	}

	pub struct KqueueCancelOp {
	pub mut:
		c &KqueueCompletion = unsafe { nil }
	}

	pub struct KqueueMachPortOp {
	pub mut:
		port   u32
		buffer KqueueReadBuffer
	}

	pub struct KqueueProcOp {
	pub mut:
		pid   int
		flags u32 = kqueue_note_exit_flags
	}

	pub enum KqueueTimerTrigger as u8 {
		// Unused with epoll
		request
		// Timer expired.
		expiration
		// Timer was canceled.
		cancel
	}

	// ReadBuffer are the various options for reading.
	pub type KqueueReadBuffer = ReadBufferArray | ReadBufferSlice

	// slice_ptr returns the active buffer as a slice that aliases the completion.
	fn (self &KqueueReadBuffer) slice_ptr() []u8 {
		return match self {
			ReadBufferSlice { self.slice }
			ReadBufferArray { unsafe { (&self.array[0]).vbytes(self.array.len) } }
		}
	}

	fn (self &KqueueReadBuffer) is_empty_slice() bool {
		return self is ReadBufferSlice && self.slice.len == 0
	}

	// WriteBuffer are the various options for writing.
	pub type KqueueWriteBuffer = WriteBufferArray | WriteBufferSlice

	fn (self &KqueueWriteBuffer) bytes() []u8 {
		return match self {
			WriteBufferSlice { self.slice }
			WriteBufferArray { unsafe { (&self.array[0]).vbytes(int(self.len)) } }
		}
	}

	// Timer that is inserted into the heap.
	pub struct KqueueHeapTimer {
	pub mut:
		// The absolute time to fire this timer next.
		next Timespec

		// Only used internally. If this is non-null and timer is
		// CANCELLED, then the timer is rearmed automatically with this
		// as the next time. The callback will not be called on the
		// cancellation.
		reset ?Timespec

		// Internal heap fields.
		heap IntrusiveHeapField[KqueueHeapTimer]

		// We point back to completion for now. When issue[1] is fixed,
		// we can juse use that from our heap fields.
		// [1]: https://github.com/ziglang/zig/issues/6611
		c &KqueueCompletion = unsafe { nil }
	}

	fn kqueue_timer_less(a &KqueueHeapTimer, b &KqueueHeapTimer) bool {
		return a.ns() < b.ns()
	}

	// Returns the nanoseconds of this timer. Note that maxInt(u64) ns is
	// 584 years so if we get any overflows we just use maxInt(u64). If
	// any software is running in 584 years waiting on this timer...
	// shame on me I guess... but I'll be dead.
	fn (self &KqueueHeapTimer) ns() u64 {
		assert self.next.tv_sec >= 0
		assert self.next.tv_nsec >= 0

		max := max_u64
		s_ns := mul_u64(u64(self.next.tv_sec), 1_000_000_000) or { return max }
		return add_u64(s_ns, u64(self.next.tv_nsec)) or { return max }
	}

	// kevent calls either kevent or kevent64 depending on the
	// target platform.
	fn kevent_syscall(kq int, changelist &Kevent, changelist_len uint, eventlist &Kevent, eventlist_len uint, timeout &Timespec) !uint {
		// Otherwise, we have to call the kevent64 variant.
		nchanges := cast_c_int(changelist_len) or { return new_error(.overflow) }
		nevents := cast_c_int(eventlist_len) or { return new_error(.overflow) }
		c_timeout := unsafe { &C.timespec(timeout) }
		for {
			mut rc := int(0)
			$if freebsd {
				// This is std.posix.kevent's native Kevent branch. Its retry/error
				// switch is identical to the source kevent64 branch below.
				rc = C.kevent(kq, changelist, nchanges, eventlist, nevents, c_timeout)
			} $else {
				rc = C.kevent64(kq, changelist, nchanges, eventlist, nevents, 0, c_timeout)
			}
			match posix_errno(rc) {
				0 { return uint(rc) }
				C.EACCES { return new_error(.access_denied) }
				C.EFAULT { panic('unreachable') }
				C.EBADF { panic('unreachable') } // Always a race condition.
				C.EINTR { continue }
				C.EINVAL { panic('unreachable') }
				C.ENOENT { return new_error(.event_not_found) }
				C.ENOMEM { return new_error(.system_resources) }
				C.ESRCH { return new_error(.process_not_found) }
				else { panic('unreachable') }
			}
		}
		return 0
	}

	// C exposes FreeBSD udata as a pointer and Darwin udata as u64.
	fn kevent_clear_userdata(mut ev Kevent) {
		$if freebsd {
			ev.udata = unsafe { nil }
		} $else {
			ev.udata = 0
		}
	}

	// kevent_init initializes a Kevent from an posix.Kevent. This is used when
	// the "ext" fields are zero.
	@[inline]
	fn kevent_init(ident u64, filter i16, flags u16, fflags u32, udata u64) Kevent {
		$if freebsd {
			return Kevent{
				ident:  uint(ident)
				filter: filter
				flags:  flags
				fflags: fflags
				data:   0
				udata:  voidptr(uint(udata))
			}
		} $else {
			return Kevent{
				ident:  ident
				filter: filter
				flags:  flags
				fflags: fflags
				data:   0
				udata:  udata
				ext:    [u64(0), 0]!
			}
		}
	}
}
