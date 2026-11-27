module datastruct

import fastmem

// CacheEntry is a key/value pair returned when put evicts the least-recently
// used entry in a full bucket.
pub struct CacheEntry[K, V] {
pub:
	key   K
	value V
}

// CacheTable is Ghostty's fixed-bucket associative cache. V cannot accept
// comptime integer parameters on a generic type, so bucket_count and
// bucket_size are immutable runtime fields initialized by cache_table.
pub struct CacheTable[K, V, X] {
pub:
	bucket_count uint
	bucket_size  u8
pub mut:
	context X
mut:
	buckets [][]CacheEntry[K, V]
}

// cache_table translates Ghostty's CacheTable type factory. Context provides
// hash(key) u64 and eql(a, b) bool, and may provide evicted(key, value).
pub fn cache_table[K, V, X](context X, bucket_count uint, bucket_size u8) CacheTable[K, V, X] {
	assert bucket_count > 0 && bucket_count & (bucket_count - 1) == 0
	return CacheTable[K, V, X]{
		context:      context
		bucket_count: bucket_count
		bucket_size:  bucket_size
		buckets:      [][]CacheEntry[K, V]{len: int(bucket_count)}
	}
}

// put appends to a non-full bucket or replaces and returns its least-recently
// used entry. Equal keys are deliberately not deduplicated.
pub fn (mut self CacheTable[K, V, X]) put(key K, value V) ?CacheEntry[K, V] {
	idx := int(self.context.hash(key) % u64(self.bucket_count))
	entry := CacheEntry[K, V]{
		key:   key
		value: value
	}
	mut bucket := self.buckets[idx]
	if bucket.len < int(self.bucket_size) {
		bucket << entry
		self.buckets[idx] = bucket
		return none
	}
	assert bucket.len == int(self.bucket_size)

	evicted := fastmem.rotate_in(mut bucket, entry)
	self.buckets[idx] = bucket
	$for method in X.methods {
		$if method.name == 'evicted' {
			self.context.evicted(evicted.key, evicted.value)
		}
	}
	return evicted
}

// get searches newest-first and promotes a hit to most-recently used.
pub fn (mut self CacheTable[K, V, X]) get(key K) ?V {
	idx := int(self.context.hash(key) % u64(self.bucket_count))
	mut bucket := self.buckets[idx]
	mut i := bucket.len
	for i > 0 {
		i--
		if self.context.eql(key, bucket[i].key) {
			entry := bucket[i]
			fastmem.rotate_once(mut bucket[i..])
			self.buckets[idx] = bucket
			return entry.value
		}
	}
	return none
}

// clear removes every entry and invokes the optional eviction callback in
// bucket order, from least to most recently used.
pub fn (mut self CacheTable[K, V, X]) clear() {
	for i, bucket in self.buckets {
		$for method in X.methods {
			$if method.name == 'evicted' {
				for entry in bucket {
					self.context.evicted(entry.key, entry.value)
				}
			}
		}
		self.buckets[i].clear()
	}
}

// The shaper instantiates CacheTable with an identity u64 context, 256
// buckets, and 8 entries per bucket.
const cache_table_bucket_count = 256
const cache_table_bucket_size = 8

struct U64CacheContext {}

fn (_ &U64CacheContext) hash(key u64) u64 {
	return key
}

fn (_ &U64CacheContext) eql(a u64, b u64) bool {
	return a == b
}

pub struct U64CacheEntry[T] {
pub:
	key   u64
	value T
}

// U64CacheTable is a fixed-capacity, bucketed LRU cache. Entries within a
// bucket are ordered from least to most recently used.
pub struct U64CacheTable[T] {
mut:
	table CacheTable[u64, T, U64CacheContext]
}

pub fn U64CacheTable.init[T]() U64CacheTable[T] {
	return U64CacheTable.init_with_buckets[T](cache_table_bucket_count)
}

pub fn U64CacheTable.init_with_buckets[T](bucket_count uint) U64CacheTable[T] {
	return U64CacheTable[T]{
		table: cache_table[u64, T, U64CacheContext](U64CacheContext{}, bucket_count,
			cache_table_bucket_size)
	}
}

// put appends a value to its bucket, evicting the least-recently-used entry
// when the bucket is full. Like Ghostty's CacheTable, this deliberately does
// not deduplicate equal keys; get searches newest-first.
pub fn (mut self U64CacheTable[T]) put(key u64, value T) ?U64CacheEntry[T] {
	evicted := self.table.put(key, value) or { return none }
	return U64CacheEntry[T]{
		key:   evicted.key
		value: evicted.value
	}
}

// get returns the newest matching value and promotes it to most-recently
// used within its bucket.
pub fn (mut self U64CacheTable[T]) get(key u64) ?T {
	return self.table.get(key)
}

pub fn (mut self U64CacheTable[T]) clear() {
	self.table.clear()
}

pub fn (self &U64CacheTable[T]) count() int {
	mut result := 0
	for bucket in self.table.buckets {
		result += bucket.len
	}
	return result
}
