module SWRCache

using Base.Threads
using Dates

export CacheEntry, SWRMemoryCache, cache_get!, clear!, invalidate!, refresh!

"""
    CacheEntry(value, expires_at, stale_until)

Represents one cached value and its serve-time boundaries.

Time semantics:
- `now <= expires_at`: value is fresh.
- `expires_at < now <= stale_until`: value is soft-expired and may be served stale.
- `now > stale_until`: value is hard-expired and must be refreshed before serving.
"""
struct CacheEntry{V}
    value::V
    # Value is fresh through this timestamp (inclusive).
    expires_at::DateTime
    # Value may still be served stale through this timestamp (inclusive).
    # After this, reads must block for refresh.
    stale_until::DateTime
    function CacheEntry{V}(value::V, expires_at::DateTime, stale_until::DateTime) where {V}
        expires_at <= stale_until || error("CacheEntry must satisfy expires_at <= stale_until.")
        new{V}(value, expires_at, stale_until)
    end
end

function isfresh(entry, now_utc=now(UTC))
    return !isnothing(entry) && now_utc <= entry.expires_at
end

function isstale(entry, now_utc=now(UTC))
    return !isnothing(entry) && (entry.expires_at < now_utc <= entry.stale_until)
end

function isrevalidate(entry, now_utc=now(UTC))
    return isnothing(entry) || (now_utc > entry.stale_until)
end

function CacheEntry(value::V, expires_at::DateTime, stale_until::DateTime) where {V}
    return CacheEntry{V}(value, expires_at, stale_until)
end

mutable struct SWRMemoryCache{F,V<:CacheEntry}
    const fetcher::F
    const lock::ReentrantLock
    @atomic entry::Union{Nothing,V}
    function SWRMemoryCache{F,V}(fetcher::F, entry::Union{Nothing,V}) where {F,V}
        new{F,V}(fetcher, ReentrantLock(), entry)
    end
end

function fetch(cache::SWRMemoryCache{F,V}) where {F,V}
    return cache.fetcher()::V
end

"""
    SWRMemoryCache(fetcher)
    SWRMemoryCache(fetcher, entry)

Constructs an in-memory cache around a `fetcher` that returns `CacheEntry` values.

`fetcher` must always return the same concrete `CacheEntry{V}` type for a given
cache instance. The one-argument constructor eagerly calls `fetcher` once to
seed the cache.
"""
function SWRMemoryCache(fetcher::F, entry::V) where {F,V}
    return SWRMemoryCache{F,V}(fetcher, entry)
end

function SWRMemoryCache(fetcher::F) where {F}
    entry = fetcher()
    return SWRMemoryCache{F,typeof(entry)}(
        fetcher,
        entry
    )
end

"""
    cache_get!(cache)

Returns the cached value using stale-while-revalidate semantics.

- Fresh entries are returned immediately.
- Soft-expired entries return stale immediately if another refresh is already
    in progress; otherwise, the calling task performs the refresh before returning.
- Hard-expired entries (or cache misses) block and refresh before returning.

Refresh work is single-flight: at most one task executes `fetcher` at a time.
"""
function cache_get!(cache::SWRMemoryCache)
    entry = @atomic :acquire cache.entry
    now_utc = now(UTC)
    if isfresh(entry, now_utc)
        return entry.value
    elseif isstale(entry, now_utc)
        trylock(cache.lock) || return entry.value
    elseif isrevalidate(entry, now_utc)
        lock(cache.lock)
    else
        error("Unexpected cache state.")
    end
    try
        entry = @atomic :monotonic cache.entry
        isfresh(entry, now_utc) && return entry.value
        entry = fetch(cache)
        @atomic :release cache.entry = entry
        return entry.value
    finally
        unlock(cache.lock)
    end
end

"""
    refresh!(cache)

Forces a refresh under the cache lock, stores the new entry, and returns the
new value.
"""
function refresh!(cache::SWRMemoryCache)
    lock(cache.lock)
    try
        entry = fetch(cache)
        @atomic :release cache.entry = entry
        return entry.value
    finally
        unlock(cache.lock)
    end
end

"""
    invalidate!(cache)

Atomically clears the current entry and returns `true` if an entry was present.
"""
function invalidate!(cache::SWRMemoryCache)
    old_entry = @atomicswap :acquire_release cache.entry = nothing
    return !isnothing(old_entry)
end

"""
    clear!(cache)

Clears the current entry and returns `cache`.
"""
function clear!(cache::SWRMemoryCache)
    @atomic :release cache.entry = nothing
    return cache
end

end
