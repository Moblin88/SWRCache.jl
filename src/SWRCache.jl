module SWRCache

using Base.Threads
using Dates

export CacheEntry, RefreshOptions, SWRMemoryCache, cache_get!, clear!, invalidate!, refresh!

Base.@kwdef struct RefreshOptions
    ttl_seconds::Float64 = 30.0
    stale_ttl_seconds::Float64 = 120.0
    refresh_on_stale_access::Bool = true
    async_refresh::Bool = true
end

mutable struct CacheEntry{V}
    value::V
    refreshed_at::DateTime
    expires_at::DateTime
    stale_until::DateTime
    last_refresh_error::Union{Nothing,Exception}
end

mutable struct SWRMemoryCache{F}
    fetcher::F
    options::RefreshOptions
    lock::ReentrantLock
    entry::Union{Nothing,CacheEntry}
    inflight::Union{Nothing,Task}
    @atomic refresh_inflight::Bool
    @atomic expires_at_unix_ms::Int64
    @atomic stale_until_unix_ms::Int64
end

function SWRMemoryCache(fetcher::F; options::RefreshOptions = RefreshOptions()) where {F}
    _validate_options(options)
    return SWRMemoryCache{F}(fetcher, options, ReentrantLock(), nothing, nothing, false, 0, 0)
end

function cache_get!(cache::SWRMemoryCache)
    while true
        now_utc = now(UTC)
        now_ms = _datetime_to_unix_ms(now_utc)
        stale_deadline_ms = @atomic cache.stale_until_unix_ms

        if stale_deadline_ms > 0 && now_ms <= stale_deadline_ms
            entry = @lock cache.lock cache.entry
            if entry !== nothing && _is_fresh(entry, now_utc)
                return entry.value
            end
            if entry !== nothing && _is_stale(entry, now_utc)
                if cache.options.refresh_on_stale_access && cache.options.async_refresh && !(@atomic cache.refresh_inflight)
                    _ensure_refresh_task!(cache)
                end
                return entry.value
            end
        end

        refresh_task = _ensure_refresh_task!(cache)
        wait(refresh_task)
    end
end

function refresh!(cache::SWRMemoryCache)
    refresh_task = _ensure_refresh_task!(cache)
    wait(refresh_task)
    return cache_get!(cache)
end

function invalidate!(cache::SWRMemoryCache)
    had_entry = @lock cache.lock begin
        existing = cache.entry !== nothing
        cache.entry = nothing
        @atomic cache.expires_at_unix_ms = 0
        @atomic cache.stale_until_unix_ms = 0
        existing
    end
    return had_entry
end

function clear!(cache::SWRMemoryCache)
    @lock cache.lock begin
        cache.entry = nothing
        @atomic cache.expires_at_unix_ms = 0
        @atomic cache.stale_until_unix_ms = 0
    end
    return cache
end

function _validate_options(options::RefreshOptions)
    options.ttl_seconds > 0 || error("RefreshOptions.ttl_seconds must be > 0.")
    options.stale_ttl_seconds >= 0 || error("RefreshOptions.stale_ttl_seconds must be >= 0.")
    return nothing
end

_is_fresh(entry::CacheEntry, now_utc::DateTime) = now_utc <= entry.expires_at
_is_stale(entry::CacheEntry, now_utc::DateTime) = now_utc <= entry.stale_until

function _ensure_refresh_task!(cache::SWRMemoryCache)
    return @lock cache.lock begin
        existing_task = cache.inflight
        if existing_task !== nothing
            existing_task
        else
            refresh_task = Threads.@spawn _refresh_value!(cache)
            cache.inflight = refresh_task
            @atomic cache.refresh_inflight = true
            errormonitor(refresh_task)
            refresh_task
        end
    end
end

_duration_milliseconds(seconds::Float64) = Millisecond(round(Int, seconds * 1000))

function _datetime_to_unix_ms(dt::DateTime)
    return round(Int64, datetime2unix(dt) * 1000)
end

function _refresh_value!(cache::SWRMemoryCache)
    refreshed_entry = nothing
    refresh_error = nothing
    try
        refreshed_value = cache.fetcher()
        refreshed_at = now(UTC)
        ttl_duration = _duration_milliseconds(cache.options.ttl_seconds)
        stale_duration = _duration_milliseconds(cache.options.stale_ttl_seconds)
        refreshed_entry = CacheEntry(
            refreshed_value,
            refreshed_at,
            refreshed_at + ttl_duration,
            refreshed_at + ttl_duration + stale_duration,
            nothing,
        )
        return refreshed_value
    catch err
        refresh_error = err
        rethrow()
    finally
        @lock cache.lock begin
            if refreshed_entry !== nothing
                cache.entry = refreshed_entry
                @atomic cache.expires_at_unix_ms = _datetime_to_unix_ms(refreshed_entry.expires_at)
                @atomic cache.stale_until_unix_ms = _datetime_to_unix_ms(refreshed_entry.stale_until)
            elseif refresh_error !== nothing
                existing = cache.entry
                if existing !== nothing
                    existing.last_refresh_error = refresh_error
                end
            else
                @atomic cache.expires_at_unix_ms = 0
                @atomic cache.stale_until_unix_ms = 0
            end
            cache.inflight = nothing
            @atomic cache.refresh_inflight = false
        end
    end
end

end
