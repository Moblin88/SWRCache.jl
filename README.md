# SWRCache.jl

[![CI](https://github.com/Moblin88/SWRCache/actions/workflows/ci.yml/badge.svg)](https://github.com/Moblin88/SWRCache/actions/workflows/ci.yml)
[![Docs](https://github.com/Moblin88/SWRCache/actions/workflows/docs.yml/badge.svg)](https://github.com/Moblin88/SWRCache/actions/workflows/docs.yml)
[![codecov](https://codecov.io/gh/Moblin88/SWRCache/branch/main/graph/badge.svg)](https://codecov.io/gh/Moblin88/SWRCache)

In-memory stale-while-revalidate cache with single-flight refresh coordination.

## Features

- Stale-while-revalidate reads (stale values are returned immediately while background refresh runs).
- Single-flight refresh for the cached value (only one active refresh at a time).
- Blocking only on cache misses or fully expired entries.
- Automatic background refresh on stale reads.

## Installation

```julia
using Pkg
Pkg.develop(path=".")
```

## Quick start

```julia
using SWRCache
using Dates

fetch_count = Ref(0)
fetcher() = begin
    fetch_count[] += 1
    sleep(0.2)
    now_utc = now(UTC)
    CacheEntry(
        "value-$(fetch_count[])",
        now_utc + Millisecond(5_000),
        now_utc + Millisecond(35_000),
    )
end

cache = SWRMemoryCache(fetcher)

value = cache_get!(cache)
```

`fetcher` is expected to return a `CacheEntry`.

`CacheEntry` time semantics are:
- `now <= expires_at`: value is fresh.
- `expires_at < now <= stale_until`: value is soft-expired and may be served stale.
- `now > stale_until`: value is hard-expired and callers block for refresh.

## GitHub setup notes

If you fork this project, update badge links and `docs/make.jl` to your repository path.
