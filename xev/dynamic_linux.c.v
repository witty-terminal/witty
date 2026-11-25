module xev

// V translation of libxev's src/dynamic.zig (pinned 34fa508) instantiated for
// Linux as `Xev(&.{ .io_uring, .epoll })`. The public declarations of the
// returned struct (dynamic, candidates, Backend, backend, detect, prefer,
// subset, superset, and the forwarded types) are in main_linux.c.v.
//
// Creates the Xev API based on a set of backend types that allows
// for dynamic choice between the various candidate backends (assuming
// they're available). For example, on Linux, this allows a consumer to
// choose between io_uring and epoll, or for automatic fallback to epoll
// to occur.
//
// If only one backend is given, the returned type is equivalent to
// the static API with no runtime conditional logic, so there is no downside
// to always using the dynamic choice variant if you wish to support
// dynamic choice.
//
// The goal of this API is to match the static Xev() (in main.zig)
// API as closely as possible. It can't be exact since this is an abstraction
// and therefore must be limited to the least common denominator of all
// backends.
//
// Since the static Xev API exposes types that can be initialized on their
// own (i.e. xev.Async.init()), this API does the same. Since we need to
// know the backend to use, this uses a global variable. The backend to use
// defaults to the first candidate backend and DOES NOT test that it is
// available. The API user should call `detect()` to set the backend to
// the first available backend.
//
// Additionally, a caller can manually set the backend to use, but this
// must be done before initializing any other types.
//
// The comptime-generated types are written out for the two candidates:
//
//   - EnumSubset(AllBackend, bes) is DynamicBackend (main_linux.c.v).
//   - Union(bes, field, false) creates a union type that can hold the
//     implementation of a given backend by common field name. Example, for
//     Async: Union(bes, "Async") produces
//
//       union {
//         io_uring: IO_Uring.Async,
//         epoll: Epoll.Async,
//       }
//
//     The union is untagged to save an extra bit of memory per
//     instance since we have the active backend from the outer struct.
//     These are the V unions named Dynamic<Type>Union, with one field per
//     candidate. If the union only has zero-sized types, a non-zero sized
//     padding entry is added (see DynamicTimerUnion).
//   - Union(bes, field, true) (TaggedUnion) is the same union with an
//     EnumSubset tag. V unions are untagged, so the owner of a tagged union
//     value keeps the tag next to it in a `tag` field.
//   - ErrorSet(bes, field) merges the given error set of every candidate. V
//     errors carry an ErrorKind (errors.v), so callbacks receive `?ErrorKind`.
//
// Zig's `@fieldParentPtr` from a backend loop or completion back to the
// dynamic wrapper is pointer arithmetic with `__offsetof`.

@[heap]
pub struct DynamicLoop {
pub mut:
	backend DynamicLoopUnion
}

pub union DynamicLoopUnion {
pub mut:
	io_uring IoUringLoop
	epoll    EpollLoop
}

pub fn DynamicLoop.init(opts Options) !DynamicLoop {
	// Select the union member after constructing the wrapper. V can emit
	// default initializers for the other member in a union literal.
	mut loop := DynamicLoop{}
	match backend() {
		.io_uring {
			backend_loop := IoUringLoop.init(opts)!
			unsafe { loop.backend.io_uring = backend_loop }
		}
		.epoll {
			backend_loop := EpollLoop.init(opts)!
			unsafe { loop.backend.epoll = backend_loop }
		}
	}
	return loop
}

pub fn (mut self DynamicLoop) deinit() {
	match backend() {
		.io_uring { unsafe { self.backend.io_uring.deinit() } }
		.epoll { unsafe { self.backend.epoll.deinit() } }
	}
}

pub fn (mut self DynamicLoop) stop() {
	match backend() {
		.io_uring { unsafe { self.backend.io_uring.stop() } }
		.epoll { unsafe { self.backend.epoll.stop() } }
	}
}

pub fn (self &DynamicLoop) stopped() bool {
	return match backend() {
		.io_uring { unsafe { self.backend.io_uring.stopped() } }
		.epoll { unsafe { self.backend.epoll.stopped() } }
	}
}

pub fn (mut self DynamicLoop) run(mode RunMode) ! {
	match backend() {
		.io_uring { unsafe { self.backend.io_uring.run(mode)! } }
		.epoll { unsafe { self.backend.epoll.run(mode)! } }
	}
}

// @fieldParentPtr("backend", @as(*Loop.Union, @fieldParentPtr("io_uring", l)))
fn DynamicLoop.from_io_uring(l &IoUringLoop) &DynamicLoop {
	return unsafe {
		&DynamicLoop(voidptr(uint(l) - __offsetof(DynamicLoopUnion, io_uring) -
			__offsetof(DynamicLoop, backend)))
	}
}

// @fieldParentPtr("backend", @as(*Loop.Union, @fieldParentPtr("epoll", l)))
fn DynamicLoop.from_epoll(l &EpollLoop) &DynamicLoop {
	return unsafe {
		&DynamicLoop(voidptr(uint(l) - __offsetof(DynamicLoopUnion, epoll) -
			__offsetof(DynamicLoop, backend)))
	}
}

@[heap]
pub struct DynamicCompletion {
pub mut:
	// Completions, unlike almost any other dynamic type in this
	// file, are tagged unions. This adds a minimal overhead to
	// the completion but is necessary to ensure that we have
	// zero-initialized the correct type for where it matters
	// (timers).
	//
	// The default is the zero value of the last candidate (epoll). It is
	// built by a function: this V's cgen garbles a union literal default
	// whose members need hoisted temporaries (EpollCompletion has an optional
	// field) when an enclosing struct literal zero-initializes a Completion.
	value DynamicCompletionUnion = dynamic_completion_default_value()
	// The tag of `value`.
	tag DynamicBackend = .epoll
}

fn dynamic_completion_default_value() DynamicCompletionUnion {
	return DynamicCompletionUnion{
		epoll: EpollCompletion{}
	}
}

pub union DynamicCompletionUnion {
pub mut:
	io_uring IoUringCompletion
	epoll    EpollCompletion
}

pub fn DynamicCompletion.init() DynamicCompletion {
	// The source initializes the value with `api.Completion.init()`, which no
	// backend declares at this commit (Zig never analyzes this function);
	// the zero value is used.
	return match backend() {
		.io_uring {
			DynamicCompletion{
				value: DynamicCompletionUnion{
					io_uring: IoUringCompletion{}
				}
				tag:   .io_uring
			}
		}
		.epoll {
			DynamicCompletion{
				value: DynamicCompletionUnion{
					epoll: EpollCompletion{}
				}
				tag:   .epoll
			}
		}
	}
}

pub fn (self &DynamicCompletion) state() CompletionState {
	return match self.tag {
		.io_uring { unsafe { self.value.io_uring.state() } }
		.epoll { unsafe { self.value.epoll.state() } }
	}
}

// This ensures that the tag is currently set for this
// completion. If it is not, it will be set to the given
// tag with a zero-initialized value.
//
// This lets users zero-intialize the completion and then
// call any watcher API on it without having to worry about
// the correct detected backend tag being set.
pub fn (mut self DynamicCompletion) ensure_tag(tag DynamicBackend) {
	if self.tag == tag {
		return
	}
	self.value = match tag {
		.io_uring {
			DynamicCompletionUnion{
				io_uring: IoUringCompletion{}
			}
		}
		.epoll {
			DynamicCompletionUnion{
				epoll: EpollCompletion{}
			}
		}
	}

	self.tag = tag
}

// @fieldParentPtr("value", @as(*Completion.Union, @fieldParentPtr("io_uring", c)))
fn DynamicCompletion.from_io_uring(c &IoUringCompletion) &DynamicCompletion {
	return unsafe {
		&DynamicCompletion(voidptr(uint(c) - __offsetof(DynamicCompletionUnion, io_uring) -
			__offsetof(DynamicCompletion, value)))
	}
}

// @fieldParentPtr("value", @as(*Completion.Union, @fieldParentPtr("epoll", c)))
fn DynamicCompletion.from_epoll(c &EpollCompletion) &DynamicCompletion {
	return unsafe {
		&DynamicCompletion(voidptr(uint(c) - __offsetof(DynamicCompletionUnion, epoll) -
			__offsetof(DynamicCompletion, value)))
	}
}

// Our read buffer supports a least common denominator of
// read targets available by all backends. The direct backend
// may support more read targets but if you need that you should
// use the backend directly and not through the dynamic API.
//
// A Zig union(enum) { slice: []u8, array: [32]u8 }, sharing the backends'
// buffer variants so conversions copy the active payload.
pub type DynamicReadBuffer = ReadBufferArray | ReadBufferSlice

// Convert a backend-specific read buffer to this
// (fromBackend(.io_uring, buf)).
pub fn DynamicReadBuffer.from_io_uring(buf IoUringReadBuffer) DynamicReadBuffer {
	return match buf {
		ReadBufferSlice {
			DynamicReadBuffer(buf)
		}
		ReadBufferArray {
			DynamicReadBuffer(buf)
		}
	}
}

// Convert a backend-specific read buffer to this
// (fromBackend(.epoll, buf)).
pub fn DynamicReadBuffer.from_epoll(buf EpollReadBuffer) DynamicReadBuffer {
	return match buf {
		ReadBufferSlice {
			DynamicReadBuffer(buf)
		}
		ReadBufferArray {
			DynamicReadBuffer(buf)
		}
	}
}

// Convert this read buffer to the backend-specific
// buffer (toBackend(.io_uring)).
pub fn (self DynamicReadBuffer) to_io_uring() IoUringReadBuffer {
	return match self {
		ReadBufferSlice {
			IoUringReadBuffer(self)
		}
		ReadBufferArray {
			IoUringReadBuffer(self)
		}
	}
}

// Convert this read buffer to the backend-specific
// buffer (toBackend(.epoll)).
pub fn (self DynamicReadBuffer) to_epoll() EpollReadBuffer {
	return match self {
		ReadBufferSlice {
			EpollReadBuffer(self)
		}
		ReadBufferArray {
			EpollReadBuffer(self)
		}
	}
}

// Our write buffer supports a least common denominator of
// write targets available by all backends. The direct backend
// may support more write targets but if you need that you should
// use the backend directly and not through the dynamic API.
//
// A Zig union(enum) { slice: []const u8, array: struct { array: [32]u8,
// len: usize } }, sharing the backends' buffer variants so conversions copy
// the active payload.
pub type DynamicWriteBuffer = WriteBufferArray | WriteBufferSlice

// Convert a backend-specific write buffer to this
// (fromBackend(.io_uring, buf)).
pub fn DynamicWriteBuffer.from_io_uring(buf IoUringWriteBuffer) DynamicWriteBuffer {
	return match buf {
		WriteBufferSlice {
			DynamicWriteBuffer(buf)
		}
		WriteBufferArray {
			DynamicWriteBuffer(buf)
		}
	}
}

// Convert a backend-specific write buffer to this
// (fromBackend(.epoll, buf)).
pub fn DynamicWriteBuffer.from_epoll(buf EpollWriteBuffer) DynamicWriteBuffer {
	return match buf {
		WriteBufferSlice {
			DynamicWriteBuffer(buf)
		}
		WriteBufferArray {
			DynamicWriteBuffer(buf)
		}
	}
}

// Convert this write buffer to the backend-specific
// buffer (toBackend(.io_uring)).
pub fn (self DynamicWriteBuffer) to_io_uring() IoUringWriteBuffer {
	return match self {
		WriteBufferSlice {
			IoUringWriteBuffer(self)
		}
		WriteBufferArray {
			IoUringWriteBuffer(self)
		}
	}
}

// Convert this write buffer to the backend-specific
// buffer (toBackend(.epoll)).
pub fn (self DynamicWriteBuffer) to_epoll() EpollWriteBuffer {
	return match self {
		WriteBufferSlice {
			EpollWriteBuffer(self)
		}
		WriteBufferArray {
			EpollWriteBuffer(self)
		}
	}
}

pub struct DynamicWriteQueue {
pub mut:
	// The default is the zero value of the last candidate (epoll).
	value DynamicWriteQueueUnion = DynamicWriteQueueUnion{
		epoll: EpollWriteQueue{}
	}
	// The tag of `value`.
	tag DynamicBackend = .epoll
}

pub union DynamicWriteQueueUnion {
pub mut:
	io_uring IoUringWriteQueue
	epoll    EpollWriteQueue
}

pub fn (mut self DynamicWriteQueue) ensure_tag(tag DynamicBackend) {
	if self.tag == tag {
		return
	}
	self.value = match tag {
		.io_uring {
			DynamicWriteQueueUnion{
				io_uring: IoUringWriteQueue{}
			}
		}
		.epoll {
			DynamicWriteQueueUnion{
				epoll: EpollWriteQueue{}
			}
		}
	}

	self.tag = tag
}

// The dynamic WriteRequest: Union(bes, "WriteRequest").
pub union DynamicWriteRequest {
pub mut:
	io_uring IoUringWriteRequest
	epoll    EpollWriteRequest
}

pub enum DynamicPollEvent as u32 {
	read = 1
}

// fromBackend(.io_uring, event)
pub fn DynamicPollEvent.from_io_uring(event IoUringPollEvent) DynamicPollEvent {
	return match event {
		.read { .read }
	}
}

// fromBackend(.epoll, event)
pub fn DynamicPollEvent.from_epoll(event EpollPollEvent) DynamicPollEvent {
	return match event {
		.read { .read }
	}
}

// toBackend(.io_uring)
pub fn (self DynamicPollEvent) to_io_uring() IoUringPollEvent {
	return match self {
		.read { .read }
	}
}

// toBackend(.epoll)
pub fn (self DynamicPollEvent) to_epoll() EpollPollEvent {
	return match self {
		.read { .read }
	}
}
