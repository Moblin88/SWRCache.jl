# SWRCache.jl

[![CI](https://github.com/Moblin88/SWRCache/actions/workflows/ci.yml/badge.svg)](https://github.com/Moblin88/SWRCache/actions/workflows/ci.yml)
[![Docs](https://github.com/Moblin88/SWRCache/actions/workflows/docs.yml/badge.svg)](https://github.com/Moblin88/SWRCache/actions/workflows/docs.yml)
[![codecov](https://codecov.io/gh/Moblin88/SWRCache/branch/main/graph/badge.svg)](https://codecov.io/gh/Moblin88/SWRCache)

In-memory stale-while-revalidate cache with single-flight refresh coordination.

## Features

- Stale-while-revalidate reads (stale values are returned immediately while background refresh runs).
- Single-flight refresh for the cached value (only one active refresh at a time).
- Blocking only on cache misses or fully expired entries.
- Structured refresh behavior via `RefreshOptions`.

## Installation

```julia
using Pkg
Pkg.develop(path=".")
```

## Quick start

```julia
using SWRCache

fetch_count = Ref(0)
fetcher() = begin
    fetch_count[] += 1
    sleep(0.2)
    "value-$(fetch_count[])"
end

cache = SWRMemoryCache(fetcher; options=RefreshOptions(
    ttl_seconds=5.0,
    stale_ttl_seconds=30.0,
    refresh_on_stale_access=true,
    async_refresh=true,
))

value = cache_get!(cache)
```

## GitHub setup notes

If you fork this project, update badge links and `docs/make.jl` to your repository path.
