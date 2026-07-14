# SWRCache.jl

`SWRCache.jl` provides an in-memory stale-while-revalidate cache with single-flight refresh behavior for one cached value.

Construct caches with `SWRMemoryCache(fetcher)` or `SWRMemoryCache(fetcher, entry)`.

## API

```@docs
CacheEntry
SWRMemoryCache
cache_get!
refresh!
invalidate!
clear!
```

## Design behavior

- `now <= expires_at`: return fresh cached value.
- `expires_at < now <= stale_until`: return stale cached value and trigger background refresh.
- `now > stale_until` (or cache miss): block until the single shared refresh completes.
