module internal_os

// V translation of Ghostty's src/os/cf_release_thread.zig.
//
// Represents the CFRelease thread. Pools of CFTypeRefs are sent to
// this thread to be released, so that their release callback logic
// doesn't block the execution of a high throughput thread like the
// renderer thread.
import datastruct
import log
import witty_macos as macos
import xev

$if macos || ios {
	pub struct CFReleaseMessageRelease {
	pub:
		// Release a slice of CFTypeRefs. V's GC frees the slice after releasing
		// all the refs.
		refs []voidptr
	}

	// Ghostty's Message union has the single `release` variant.
	pub struct CFReleaseMessage {
	pub:
		release CFReleaseMessageRelease
	}

	// The type used for sending messages to the thread. For now this is
	// hardcoded with a capacity. We can make this a comptime parameter in
	// the future if we want it configurable.
	pub type CFReleaseMailbox = datastruct.BlockingQueue[CFReleaseMessage]

	// create allocates the mailbox with its fixed source capacity. V generics have
	// no integer parameters, so the capacity is supplied here instead of the type.
	pub fn CFReleaseMailbox.create() !&datastruct.BlockingQueue[CFReleaseMessage] {
		return datastruct.BlockingQueue.create[CFReleaseMessage](64)!
	}

	pub struct CFReleaseThreadFlags {
	mut:
		value u8
	}

	// This is set to true only when an abnormal exit is detected. It
	// tells our mailbox system to drain and ignore all messages.
	pub fn (f CFReleaseThreadFlags) drain() bool {
		return f.value & 0b1 != 0
	}

	pub fn (mut f CFReleaseThreadFlags) set_drain(v bool) {
		if v {
			f.value |= 0b1
		} else {
			f.value &= ~u8(0b1)
		}
	}

	pub struct CFReleaseThread {
	pub mut:
		// The main event loop for the thread. The user data of this loop
		// is always the allocator used to create the loop. This is a convenience
		// so that users of the loop always have an allocator.
		loop xev.Loop

		// This can be used to wake up the thread.
		wakeup   xev.Async
		wakeup_c xev.Completion

		// This can be used to stop the thread on the next loop iteration.
		stop   xev.Async
		stop_c xev.Completion

		// The mailbox that can be used to send this thread messages. Note
		// this is a blocking queue so if it is full you will get errors (or block).
		mailbox &datastruct.BlockingQueue[CFReleaseMessage] = unsafe { nil }

		flags CFReleaseThreadFlags
	}

	// Initialize the thread. This does not START the thread. This only sets
	// up all the internal state necessary prior to starting the thread. It
	// is up to the caller to start the thread with the threadMain entrypoint.
	pub fn CFReleaseThread.init() !CFReleaseThread {
		// Zig's errdefers are emulated by reached defers that run until init succeeds.
		mut init_ok := false

		// Create our event loop.
		mut loop := xev.Loop.init(xev.Options{})!
		defer {
			if !init_ok {
				loop.deinit()
			}
		}

		// This async handle is used to "wake up" the thread to collect objects.
		mut wakeup_h := xev.Async.init()!
		defer {
			if !init_ok {
				wakeup_h.deinit()
			}
		}

		// This async handle is used to stop the loop and force the thread to end.
		mut stop_h := xev.Async.init()!
		defer {
			if !init_ok {
				stop_h.deinit()
			}
		}

		// The mailbox for messaging this thread
		mailbox := CFReleaseMailbox.create()!

		init_ok = true
		return CFReleaseThread{
			loop:    loop
			wakeup:  wakeup_h
			stop:    stop_h
			mailbox: mailbox
		}
	}

	// Clean up the thread. This is only safe to call once the thread
	// completes executing; the caller must join prior to this.
	pub fn (mut self CFReleaseThread) deinit() {
		self.stop.deinit()
		self.wakeup.deinit()
		self.loop.deinit()

		// Nothing can possibly access the mailbox anymore, destroy it.
		unsafe {
			self.mailbox.destroy()
		}
	}

	// The main entrypoint for the thread.
	pub fn (mut self CFReleaseThread) thread_main() {
		// Call child function so we can use errors...
		self.thread_main_() or { log.warn('error in cf release thread err=${err}') }

		// If our loop is not stopped, then we need to keep running so that
		// messages are drained and we can wait for the surface to send a stop
		// message.
		if !self.loop.stopped() {
			log.warn('abrupt cf release thread exit detected, starting xev to drain mailbox')
			defer {
				log.debug('cf release thread fully exiting after abnormal failure')
			}
			self.flags.set_drain(true)
			self.loop.run(.until_done) or {
				log.error('failed to start xev loop for draining err=${err}')
			}
		}
	}

	fn (mut self CFReleaseThread) thread_main_() ! {
		defer {
			log.debug('cf release thread exited')
		}
		// Right now, on Darwin, `std.Thread.setName` can only name the current
		// thread, and we have no way to get the current thread from within it,
		// so instead we use this code to name the thread instead.
		$if macos || ios {
			set_thread_name('cf_release')
		}

		// Start the async handlers. We start these first so that they're
		// registered even if anything below fails so we can drain the mailbox.
		self.wakeup.wait(mut self.loop, &self.wakeup_c, self, cf_release_thread_wakeup_callback)
		self.stop.wait(mut self.loop, &self.stop_c, self, cf_release_thread_stop_callback)

		// Run
		log.debug('starting cf release thread')
		defer {
			log.debug('starting cf release thread shutdown')
		}
		self.loop.run(.until_done)!
	}

	// Drain the mailbox, handling all the messages in our terminal implementation.
	fn (mut self CFReleaseThread) drain_mailbox() ! {
		// If we're draining, we just drain the mailbox and return.
		if self.flags.drain() {
			for {
				self.mailbox.pop() or { break }
			}
			return
		}

		for {
			message := self.mailbox.pop() or { break }
			for ref in message.release.refs {
				macos.cf_release(ref)
			}
		}
	}

	fn cf_release_thread_wakeup_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
		if err := r {
			log.error('error in wakeup err=${err}')
			return .rearm
		}

		mut t := unsafe { &CFReleaseThread(self_) }

		// When we wake up, we check the mailbox. Mailbox producers should
		// wake up our thread after publishing.
		t.drain_mailbox() or { log.error('error draining mailbox err=${err}') }

		return .rearm
	}

	fn cf_release_thread_stop_callback(self_ voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
		if _ := r {
			panic('unreachable')
		}
		mut t := unsafe { &CFReleaseThread(self_) }
		t.loop.stop()
		return .disarm
	}
}
