module renderer

import configpkg
import datastruct
import internal_os
import xev

struct RedrawCapture {
mut:
	count int
}

fn capture_redraw(data voidptr) {
	mut capture := unsafe { &RedrawCapture(data) }
	capture.count++
}

fn test_renderer_mailbox_is_bounded_and_fifo() {
	mut mailbox := Mailbox.create()!
	defer {
		mailbox.destroy()
	}

	assert renderer_mailbox_capacity == 64
	for i in 0 .. renderer_mailbox_capacity {
		assert mailbox.push(RendererMessage(InspectorMessage{
			active: i % 2 == 0
		}), datastruct.blocking_queue_instant) == u32(i + 1)
	}
	assert mailbox.push(RendererMessage(InspectorMessage{
		active: true
	}), datastruct.blocking_queue_instant) == 0

	for i in 0 .. renderer_mailbox_capacity {
		msg := mailbox.pop() or {
			assert false, 'message ${i} should be present'
			return
		}
		match msg {
			InspectorMessage {
				assert msg.active == (i % 2 == 0)
			}
			else {
				assert false, 'unexpected renderer message type'
			}
		}
	}
	assert mailbox.pop() == none
}

// renderer_test_thread builds a thread with live xev handles and no OS
// thread, so tests can drive the loop directly.
fn renderer_test_thread(render &Renderer, config ThreadDerivedConfig, flags ThreadFlags) !RendererThread {
	return RendererThread{
		loop:     xev.Loop.init(xev.Options{})!
		wakeup:   xev.Async.init()!
		stop:     xev.Async.init()!
		render_h: xev.Timer.init()!
		draw_h:   xev.Timer.init()!
		draw_now: xev.Async.init()!
		cursor_h: xev.Timer.init()!
		renderer: unsafe { render }
		mailbox:  Mailbox.create()!
		config:   config
		flags:    flags
	}
}

struct RendererTestAsyncCount {
mut:
	count int
}

fn renderer_test_count_async(ud voidptr, _ &xev.Loop, _ &xev.Completion, r ?xev.ErrorKind) xev.CallbackAction {
	if _ := r {
		panic('unreachable')
	}
	mut counter := unsafe { &RendererTestAsyncCount(ud) }
	counter.count++
	return .rearm
}

fn test_display_link_callback_notifies_draw_now() ! {
	mut render := Renderer{}
	mut render_thread := renderer_test_thread(&render, ThreadDerivedConfig{}, ThreadFlags{})!
	defer {
		render_thread.deinit()
	}
	mut counter := RendererTestAsyncCount{}
	render_thread.draw_now.wait(mut render_thread.loop, &render_thread.draw_now_c, &counter,
		renderer_test_count_async)
	render_thread.loop.run(.no_wait)!
	assert counter.count == 0

	// The display link only exists on macOS.
	$if macos {
		mut flags_out := u64(0)
		assert renderer_display_link_callback(unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, &flags_out, voidptr(&render_thread.draw_now)) == 0
		render_thread.loop.run(.no_wait)!
		assert counter.count == 1
	}
}

fn test_renderer_thread_stop_callback_ends_loop() ! {
	mut render := Renderer{}
	mut render_thread := renderer_test_thread(&render, ThreadDerivedConfig{}, ThreadFlags{})!
	defer {
		render_thread.deinit()
	}
	render_thread.stop.wait(mut render_thread.loop, &render_thread.stop_c, &render_thread,
		renderer_thread_stop_callback)
	render_thread.stop.notify()!
	render_thread.loop.run(.until_done)!
	assert render_thread.loop.stopped()
}

fn test_renderer_thread_cursor_blink_interval() {
	assert cursor_blink_interval_ms == 600
	assert draw_interval == 8
	if internal_os.running_on_valgrind() > 0 {
		assert cursor_blink_interval() == 3_000
	} else {
		assert cursor_blink_interval() == 600
	}
}

fn test_renderer_thread_flags_match_source_defaults() {
	flags := ThreadFlags{}
	assert !flags.cursor_blink_visible()
	assert !flags.has_inspector()
	assert flags.visible()
	assert flags.focused()
	assert sizeof(ThreadFlags) == 1
}

fn test_renderer_thread_derived_config_retains_shader_animation_type() {
	mut config := configpkg.Config.default_config()
	for animation in [configpkg.CustomShaderAnimation.false_, .true_, .always] {
		config.custom_shader_animation = animation
		derived := ThreadDerivedConfig.init(&config)
		assert derived.custom_shader_animation == animation
	}
}

fn test_renderer_thread_disabled_draw_keeps_armed_completion() ! {
	mut render := Renderer{ has_custom_shaders: true }
	mut render_thread := renderer_test_thread(&render, ThreadDerivedConfig{
		custom_shader_animation: .always
	}, ThreadFlags{})!
	defer {
		render_thread.deinit()
	}
	render_thread.sync_draw_timer()
	assert render_thread.draw_active
	assert render_thread.draw_c.state() == .active

	// Disabling the animation stops the timer only on its next iteration.
	render_thread.config.custom_shader_animation = .false_
	render_thread.sync_draw_timer()
	assert !render_thread.draw_active
	assert render_thread.draw_c.state() == .active

	render_thread.loop.run(.until_done)!
	assert render_thread.draw_c.state() == .dead
}

fn test_renderer_thread_active_draw_rearms_completion() ! {
	mut render := Renderer{}
	mut flags := ThreadFlags{}
	flags.set_focused(false)
	mut render_thread := renderer_test_thread(&render, ThreadDerivedConfig{
		custom_shader_animation: .always
	}, flags)!
	defer {
		render_thread.deinit()
	}
	render_thread.draw_from_app_thread = true
	render_thread.sync_draw_timer()
	assert render_thread.draw_c.state() == .dead

	render.has_custom_shaders = true
	render_thread.sync_draw_timer()
	// An already active draw timer is not started twice.
	render_thread.sync_draw_timer()
	assert render_thread.draw_c.state() == .active

	// The callback rearms while the animation stays active.
	render_thread.loop.run(.once)!
	assert render_thread.draw_c.state() == .active

	// A failed rebuild removes the animation source before the next tick.
	render.has_custom_shaders = false
	render_thread.loop.run(.until_done)!
	assert !render_thread.draw_active
	assert render_thread.draw_c.state() == .dead
}

fn test_shader_animation_follows_focus_and_visibility() ! {
	mut render := Renderer{ has_custom_shaders: true, focused: true }
	mut render_thread := renderer_test_thread(&render, ThreadDerivedConfig{
		custom_shader_animation: .true_
	}, ThreadFlags{})!
	defer {
		render_thread.deinit()
	}
	assert render.has_animations()
	assert render_thread.should_animate()

	render.set_focus(false)!
	render_thread.flags.set_focused(false)
	assert !render.has_animations()
	assert !render_thread.should_animate()

	render.config.custom_shader_animation = .always
	render_thread.config.custom_shader_animation = .always
	assert render.has_animations()
	assert render_thread.should_animate()

	render_thread.flags.set_visible(false)
	assert !render_thread.should_animate()
	render_thread.flags.set_visible(true)

	render.config.custom_shader_animation = .false_
	render_thread.config.custom_shader_animation = .false_
	assert !render.has_animations()
	assert !render_thread.should_animate()
}

fn test_renderer_thread_routes_app_thread_draws_through_redraw_callback() {
	mut capture := RedrawCapture{}
	mut render := Renderer{}
	mut render_thread := RendererThread{
		renderer: &render
		draw_from_app_thread: true
		app_redraw: Wakeup{
			user_data: voidptr(&capture)
			notify_fn: capture_redraw
		}
	}
	render_thread.draw_frame(false)
	assert capture.count == 1

	render_thread.flags.set_visible(false)
	render_thread.draw_frame(true)
	assert capture.count == 1
}
