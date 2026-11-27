module witty_macos

import math

// UpdateViewModel.swift and UpdateState, translated without a SwiftUI dependency.
// The native driver retains Sparkle's Objective-C blocks for these callbacks.
pub enum UpdateStateKind { idle permission_request checking update_available not_found error downloading extracting installing }
pub enum UpdateChoice { skip install dismiss }

pub struct NativeUpdateConfig {
pub:
	auto_update ?int
	channel string = 'stable'
}

pub struct UpdateCallback {
pub:
	call fn (voidptr, voidptr, int) = empty_update_callback
	context voidptr
	owner voidptr
}

fn empty_update_callback(_context voidptr, _owner voidptr, _value int) {}
pub fn (callback UpdateCallback) invoke(value int) { callback.call(callback.context, callback.owner, value) }

pub struct UpdateState {
pub:
	kind UpdateStateKind
	version string
	error_description string
	expected_length ?u64
	downloaded u64
	extraction_progress f64
	auto_update bool
	release_notes_url string
	release_notes_label string
	object voidptr
	cancel_callback UpdateCallback
	reply UpdateCallback
	acknowledgement UpdateCallback
	retry UpdateCallback
	dismiss UpdateCallback
}

pub fn (state UpdateState) is_installable() bool {
	return state.kind in [.checking, .update_available, .downloading, .extracting, .installing]
}

pub fn (state UpdateState) cancel() {
	match state.kind {
		.checking, .downloading { state.cancel_callback.invoke(0) }
		.update_available { state.reply.invoke(int(UpdateChoice.dismiss)) }
		.not_found { state.acknowledgement.invoke(0) }
		.error { state.dismiss.invoke(0) }
		else {}
	}
}

pub fn (state UpdateState) confirm() {
	if state.kind == .update_available { state.reply.invoke(int(UpdateChoice.install)) }
}

pub fn (lhs UpdateState) equals(rhs UpdateState) bool {
	if lhs.kind != rhs.kind { return false }
	return match lhs.kind {
		.update_available { lhs.version == rhs.version }
		.error { lhs.error_description == rhs.error_description }
		.downloading { lhs.downloaded == rhs.downloaded && lhs.expected_length == rhs.expected_length }
		.extracting { lhs.extraction_progress == rhs.extraction_progress }
		.installing { lhs.auto_update == rhs.auto_update }
		else { true }
	}
}

pub fn (state UpdateState) text() string {
	return match state.kind {
		.idle { '' }
		.permission_request { 'Enable Automatic Updates?' }
		.checking { 'Checking for Updates…' }
		.update_available { if state.version.len > 0 { 'Update Available: ${state.version}' } else { 'Update Available' } }
		.downloading {
			if expected := state.expected_length { if expected > 0 { return 'Downloading: ${math.round_to_even(f64(state.downloaded) / f64(expected) * 100):.0f}%' } }
			'Downloading…'
		}
		.extracting { 'Preparing: ${math.round_to_even(state.extraction_progress * 100):.0f}%' }
		.installing { if state.auto_update { 'Restart to Complete Update' } else { 'Installing…' } }
		.not_found { 'No Updates Available' }
		.error { state.error_description }
	}
}

pub fn (state UpdateState) max_width_text() string {
	return match state.kind { .downloading { 'Downloading: 100%' } .extracting { 'Preparing: 100%' } else { state.text() } }
}

pub fn (state UpdateState) icon_name() ?string {
	return match state.kind {
		.idle { none }
		.permission_request { 'questionmark.circle' }
		.checking { 'arrow.triangle.2.circlepath' }
		.update_available { 'shippingbox.fill' }
		.downloading { 'arrow.down.circle' }
		.extracting { 'shippingbox' }
		.installing { 'power.circle' }
		.not_found { 'info.circle' }
		.error { 'exclamationmark.triangle.fill' }
	}
}

pub fn (state UpdateState) description() string {
	return match state.kind {
		.idle { '' }
		.permission_request { 'Configure automatic update preferences' }
		.checking { 'Please wait while we check for available updates' }
		.update_available { if state.release_notes_label.len > 0 { state.release_notes_label } else { 'Download and install the latest version' } }
		.downloading { 'Downloading the update package' }
		.extracting { 'Extracting and preparing the update' }
		.installing { if state.auto_update { 'Restart to Complete Update' } else { 'Installing update and preparing to restart' } }
		.not_found { 'You are running the latest version' }
		.error { 'An error occurred during the update process' }
	}
}

pub fn (state UpdateState) badge() ?string {
	match state.kind {
		.update_available { if state.version.len > 0 { return state.version } }
		.downloading { if expected := state.expected_length { if expected > 0 { return '${math.round_to_even(f64(state.downloaded) / f64(expected) * 100):.0f}%' } } }
		.extracting { return '${math.round_to_even(state.extraction_progress * 100):.0f}%' }
		else {}
	}
	return none
}

// Semantic colors map one-for-one to the source SwiftUI/NSColor values.
pub fn (state UpdateState) icon_color() string {
	return match state.kind { .permission_request { 'white' } .update_available { 'accent' } .error { 'orange' } else { 'secondary' } }
}
pub fn (state UpdateState) foreground_color() string {
	return match state.kind { .permission_request, .update_available, .not_found { 'white' } .error { 'orange' } else { 'primary' } }
}
pub fn (state UpdateState) background_color() string {
	return match state.kind { .permission_request { 'blue_black_0.3' } .update_available { 'accent' } .not_found { 'blue_black_0.5' } .error { 'orange_0.2' } else { 'control' } }
}

fn math_round_update_percentage(value f64) string {
	return '${math.round_to_even(value * 100):.0f}'
}
