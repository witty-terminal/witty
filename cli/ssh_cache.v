module cli

import internal_os
import os
import math
import os.filelock
import time
import zig_fmt

const max_ssh_cache_size = 512 * 1024

pub struct SshCacheEntry {
pub:
	hostname         string
	timestamp        i64
	terminfo_version string
}

pub fn SshCacheEntry.parse(line string) ?SshCacheEntry {
	trimmed := line.trim(' \t\r\n')
	if trimmed.len == 0 {
		return none
	}
	parts := trimmed.split('|').filter(it.len > 0)
	if parts.len < 2 {
		return none
	}
	timestamp := parse_ssh_timestamp(parts[1]) or { return none }
	return SshCacheEntry{
		hostname:         parts[0]
		timestamp:        timestamp
		terminfo_version: if parts.len >= 3 { parts[2] } else { 'xterm-witty' }
	}
}

// Direct translation of `std.fmt.parseInt(i64, timestamp, 10)`.
fn parse_ssh_timestamp(input string) ?i64 {
	return zig_fmt.parse_int_signed(input, 64, 10) or { return none }
}

pub fn (entry SshCacheEntry) format() string {
	return '${entry.hostname}|${entry.timestamp}|${entry.terminfo_version}\n'
}

pub fn (entry SshCacheEntry) is_expired(expire_days ?u32) bool {
	days := expire_days or { return false }
	age_seconds := saturating_sub_i64(time.now().unix(), entry.timestamp)
	return age_seconds / i64(24 * 60 * 60) > i64(days)
}

pub enum SshCacheAddResult as u8 {
	added
	updated
}

pub struct SshDiskCache {
pub:
	path string
}

// default_path resolves `${XDG_STATE_HOME}/<program>/ssh_cache`
// without creating the directory. Path creation belongs to cache mutation.
pub fn SshDiskCache.default_path(program string) !string {
	state_dir := internal_os.state(internal_os.Options{ subdir: program })!
	return os.join_path(state_dir, 'ssh_cache')
}

pub fn (cache SshDiskCache) clear() ! {
	os.rm(cache.path) or {
		if os.exists(cache.path) {
			return err
		}
	}
}

pub fn (cache SshDiskCache) add(hostname string) !SshCacheAddResult {
	if !valid_ssh_cache_key(hostname) {
		return error('hostname is invalid')
	}
	cache.ensure_file()!
	mut file_lock := filelock.new_file(cache.path, filelock.LockOptions{})
	mut acquired := false
	$if !windows {
		if !file_lock.try_acquire() {
			return error('cache is locked')
		}
		acquired = true
	}
	defer {
		if acquired {
			file_lock.release()
		}
	}

	mut entries := cache.read_entries()!
	result := if hostname in entries { SshCacheAddResult.updated } else { SshCacheAddResult.added }
	terminfo_version := if existing := entries[hostname] {
		existing.terminfo_version
	} else {
		'xterm-witty'
	}
	entries[hostname] = SshCacheEntry{
		hostname:         hostname
		timestamp:        time.now().unix()
		terminfo_version: terminfo_version
	}
	cache.write_entries(entries, none)!
	return result
}

pub fn (cache SshDiskCache) remove(hostname string) ! {
	if !valid_ssh_cache_key(hostname) {
		return error('hostname is invalid')
	}
	if !os.exists(cache.path) {
		return
	}
	os.chmod(cache.path, 0o600)!
	mut file_lock := filelock.new_file(cache.path, filelock.LockOptions{})
	mut acquired := false
	$if !windows {
		if !file_lock.try_acquire() {
			return error('cache is locked')
		}
		acquired = true
	}
	defer {
		if acquired {
			file_lock.release()
		}
	}
	mut entries := cache.read_entries()!
	entries.delete(hostname)
	cache.write_entries(entries, none)!
}

pub fn (cache SshDiskCache) contains(hostname string) !bool {
	if !valid_ssh_cache_key(hostname) {
		return error('hostname is invalid')
	}
	entries := cache.read_entries()!
	return hostname in entries
}

pub fn (cache SshDiskCache) list() !map[string]SshCacheEntry {
	return cache.read_entries()
}

// deinit_entries releases a map returned by list. V's map keys and values are
// garbage-collected, so clearing the container is the complete counterpart to
// Ghostty's allocator-backed entry teardown.
pub fn SshDiskCache.deinit_entries(mut entries map[string]SshCacheEntry) {
	entries.clear()
}

fn (cache SshDiskCache) ensure_file() ! {
	dir := os.dir(cache.path)
	if dir.len == 0 || dir == '.' {
		return error('invalid cache path')
	}
	os.mkdir_all(dir)!
	ssh_create_file(cache.path)!
}

fn (cache SshDiskCache) read_entries() !map[string]SshCacheEntry {
	mut result := map[string]SshCacheEntry{}
	if !os.exists(cache.path) {
		return result
	}
	mut file := os.open(cache.path)!
	defer { file.close() }
	mut bytes := []u8{cap: max_ssh_cache_size}
	mut chunk := []u8{len: 4096}
	for bytes.len < max_ssh_cache_size {
		count := math.min(chunk.len, max_ssh_cache_size - bytes.len)
		read := $if windows {
			int(C._read(file.fd, chunk.data, u32(count)))
		} $else {
			C.read(file.fd, chunk.data, uint(count))
		}
		if read < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if read == 0 { break }
		bytes << chunk[..int(read)]
	}
	// Reader.allocRemaining(.limited(n)) rejects reaching the bound,
	// including an exactly-n-byte stream, without reading beyond it.
	if bytes.len == max_ssh_cache_size { return error('StreamTooLong') }
	content := bytes.bytestr()
	for line in content.split_into_lines() {
		entry := SshCacheEntry.parse(line) or { continue }
		if existing := result[entry.hostname] {
			if entry.timestamp <= existing.timestamp {
				continue
			}
		}
		result[entry.hostname] = entry
	}
	return result
}

fn (cache SshDiskCache) write_entries(entries map[string]SshCacheEntry, expire_days ?u32) ! {
	dir := os.dir(cache.path)
	if dir.len == 0 || dir == '.' {
		return error('invalid cache path')
	}
	mut atomic_file := SshAtomicFile.init(cache.path)!
	defer { atomic_file.deinit() }
	for _, entry in entries {
		if !entry.is_expired(expire_days) {
			atomic_file.write(entry.format())!
		}
	}
	atomic_file.finish()!
}

pub fn valid_ssh_cache_key(key string) bool {
	if key.len == 0 {
		return false
	}
	at := key.index_u8(`@`)
	if at >= 0 {
		return valid_ssh_user(key[..at]) && valid_ssh_host(key[at + 1..])
	}
	return valid_ssh_host(key)
}

fn valid_ssh_host(host string) bool {
	if internal_os.is_valid(host) {
		return true
	}
	return valid_ipv6_literal(host)
}

// valid_ipv6_literal accepts exactly the RFC 4291 text forms V's
// net.canonical_ipv6 parses (full, `::`-compressed, dotted-quad tail). It is
// local because V 0.5.2's net module does not compile for iOS targets.
fn valid_ipv6_literal(s string) bool {
	if s.len == 0 || s.count('::') > 1 {
		return false
	}
	compressed := s.contains('::')
	head := if compressed { s.all_before('::') } else { s }
	tail := if compressed { s.all_after('::') } else { '' }
	mut head_groups := if head.len == 0 { []string{} } else { head.split(':') }
	mut tail_groups := if tail.len == 0 { []string{} } else { tail.split(':') }
	mut words := 0
	// A dotted quad may only be the final group and counts as two words.
	if compressed && tail_groups.len > 0 && tail_groups.last().contains('.') {
		if !valid_dotted_quad(tail_groups.last()) {
			return false
		}
		tail_groups = tail_groups[..tail_groups.len - 1].clone()
		words += 2
	} else if !compressed && head_groups.len > 0 && head_groups.last().contains('.') {
		if !valid_dotted_quad(head_groups.last()) {
			return false
		}
		head_groups = head_groups[..head_groups.len - 1].clone()
		words += 2
	}
	for group in head_groups {
		if !valid_hex_group(group) {
			return false
		}
	}
	for group in tail_groups {
		if !valid_hex_group(group) {
			return false
		}
	}
	words += head_groups.len + tail_groups.len
	return if compressed { words < 8 } else { words == 8 }
}

fn valid_hex_group(group string) bool {
	if group.len == 0 || group.len > 4 {
		return false
	}
	for c in group {
		if !c.is_hex_digit() {
			return false
		}
	}
	return true
}

fn valid_dotted_quad(quad string) bool {
	parts := quad.split('.')
	if parts.len != 4 {
		return false
	}
	for part in parts {
		if part.len == 0 || part.len > 3 {
			return false
		}
		for c in part {
			if !c.is_digit() {
				return false
			}
		}
		if part.int() > 255 {
			return false
		}
	}
	return true
}

fn valid_ssh_user(user string) bool {
	if user.len == 0 || user.len > 64 {
		return false
	}
	for c in user.bytes() {
		if !c.is_alnum() && c !in [`_`, `-`, `.`] {
			return false
		}
	}
	return true
}

fn saturating_sub_i64(lhs i64, rhs i64) i64 {
	if rhs >= lhs {
		return 0
	}
	if rhs < 0 && lhs > max_i64 + rhs {
		return max_i64
	}
	return lhs - rhs
}

pub struct SshCacheOptions {
pub mut:
	clear       bool
	add         ?string
	remove      ?string
	host        ?string
	expire_days ?u32
}

pub fn (opts SshCacheOptions) deinit() {
	_ = opts
}

pub fn (opts SshCacheOptions) help() ! {
	_ = opts
	action_options_help()!
}

pub struct SshCacheResult {
pub:
	code   int
	output string
	errors string
}

pub fn ssh_cache(args []string) !SshCacheResult {
	opts := parse_ssh_cache_options(args)!
	return run_inner(opts)
}

// run_inner executes parsed SSH-cache options using the standard disk cache.
pub fn run_inner(opts SshCacheOptions) !SshCacheResult {
	cache := SshDiskCache{
		path: SshDiskCache.default_path('witty')!
	}
	return run_inner_with_cache(cache, opts)
}

fn run_inner_with_cache(cache SshDiskCache, opts SshCacheOptions) !SshCacheResult {
	// This is parsed by upstream but currently not forwarded to DiskCache.
	_ = opts.expire_days
	if opts.clear {
		cache.clear()!
		return SshCacheResult{
			output: 'Cache cleared.\n'
		}
	}
	if host := opts.add {
		result := cache.add(host) or { return ssh_cache_operation_error('add', host, err) }
		return SshCacheResult{
			output: match result {
				.added { "Added '${host}' to cache.\n" }
				.updated { "Updated '${host}' cache entry.\n" }
			}
		}
	}
	if host := opts.remove {
		cache.remove(host) or { return ssh_cache_operation_error('remove', host, err) }
		return SshCacheResult{
			output: "Removed '${host}' from cache.\n"
		}
	}
	if host := opts.host {
		cached := cache.contains(host) or { return ssh_cache_operation_error('check', host, err) }
		return SshCacheResult{
			code:   if cached { 0 } else { 1 }
			output: if cached {
				"'${host}' has Witty terminfo installed.\n"
			} else {
				"'${host}' does not have Witty terminfo installed.\n"
			}
		}
	}
	entries := cache.list()!
	return SshCacheResult{
		output: format_ssh_cache_entries(entries, time.now().unix())
	}
}

pub fn run_ssh_cache(args []string) !int {
	result := ssh_cache(args)!
	print(result.output)
	eprint(result.errors)
	return result.code
}

fn parse_ssh_cache_options(args []string) !SshCacheOptions {
	return parse_action_options[SshCacheOptions](args)
}

fn ssh_cache_operation_error(operation string, host string, err IError) SshCacheResult {
	if err.msg() == 'hostname is invalid' {
		return SshCacheResult{
			code:   1
			errors: "Error: Invalid hostname format '${host}'\nExpected format: hostname or user@hostname\n"
		}
	}
	if err.msg() == 'cache is locked' {
		return SshCacheResult{
			code:   1
			errors: 'Error: Cache is busy, try again\n'
		}
	}
	description := match operation {
		'add' { "add '${host}' to cache" }
		'remove' { "remove '${host}' from cache" }
		else { "check host '${host}' in cache" }
	}

	return SshCacheResult{
		code:   1
		errors: 'Error: Unable to ${description}. Error: ${err}\n'
	}
}

fn format_ssh_cache_entries(entries map[string]SshCacheEntry, now i64) string {
	if entries.len == 0 {
		return 'No hosts in cache.\n'
	}
	mut values := entries.values()
	values.sort(a.hostname < b.hostname)
	mut lines := ['Cached hosts (${values.len}):']
	for entry in values {
		age_days := (now - entry.timestamp) / i64(24 * 60 * 60)
		age := if age_days == 0 {
			'today'
		} else if age_days == 1 {
			'yesterday'
		} else {
			'${age_days} days ago'
		}
		lines << '  ${entry.hostname} (${age})'
	}
	return output_lines(lines)
}
