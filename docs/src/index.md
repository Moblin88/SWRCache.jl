# SWRCache.jl

`SWRCache.jl` provides an in-memory stale-while-revalidate cache with single-flight refresh behavior for one cached value.

## API

```@docs
RefreshOptions
CacheEntry
SWRMemoryCache
cache_get!
refresh!
invalidate!
clear!
```

## Design behavior

- Fresh entry: return cached value.
- Stale entry: return cached value immediately and trigger background refresh (if enabled).
- Expired entry or miss: block until the single shared refresh completes.
