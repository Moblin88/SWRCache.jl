using TestItems

@testitem "Fresh values are served without refresh" begin
    using SWRCache
    using Test
    using Dates

    fetch_count = Ref(0)
    function fetcher()
        fetch_count[] += 1
        now_utc = now(UTC)
        return CacheEntry(
            "value-$(fetch_count[])",
            now_utc + Millisecond(500),
            now_utc + Millisecond(1000),
        )
    end
    cache = SWRMemoryCache(fetcher)

    first_value = @inferred cache_get!(cache)
    second_value = @inferred cache_get!(cache)

    @test first_value == second_value
    @test fetch_count[] == 1
end

@testitem "Stale reads refresh and return the updated value" begin
    using SWRCache
    using Test
    using Dates

    fetch_count = Ref(0)
    function fetcher()
        fetch_count[] += 1
        sleep(0.15)
        now_utc = now(UTC)
        return CacheEntry(
            fetch_count[],
            now_utc + Millisecond(200),
            now_utc + Millisecond(600),
        )
    end
    cache = SWRMemoryCache(fetcher)

    @test @inferred(cache_get!(cache)) == 1
    sleep(0.22)

    @test @inferred(cache_get!(cache)) == 2
end

@testitem "Expired reads block for refresh and return the updated value" begin
    using SWRCache
    using Test
    using Dates

    fetch_count = Ref(0)
    function fetcher()
        fetch_count[] += 1
        sleep(0.2)
        now_utc = now(UTC)
        return CacheEntry(
            "refresh-$(fetch_count[])",
            now_utc + Millisecond(40),
            now_utc + Millisecond(70),
        )
    end
    cache = SWRMemoryCache(fetcher)

    @test @inferred(cache_get!(cache)) == "refresh-1"
    sleep(0.1)

    @test @inferred(cache_get!(cache)) == "refresh-2"
end

@testitem "Manual invalidation and refresh API" begin
    using SWRCache
    using Test
    using Dates

    fetch_count = Ref(0)
    function fetcher()
        fetch_count[] += 1
        now_utc = now(UTC)
        return CacheEntry(
            fetch_count[],
            now_utc + Millisecond(500),
            now_utc + Millisecond(1000),
        )
    end
    cache = SWRMemoryCache(fetcher)

    @test @inferred(cache_get!(cache)) == 1
    @test invalidate!(cache)
    @test !invalidate!(cache)
    @test @inferred(cache_get!(cache)) == 2
    @test @inferred(refresh!(cache)) == 3
    clear!(cache)
    @test @inferred(cache_get!(cache)) == 4
end

@testitem "Fresh fast-path reads do not block on cache lock" begin
    using SWRCache
    using Test
    using Dates

    fetch_count = Ref(0)
    function fetcher()
        fetch_count[] += 1
        now_utc = now(UTC)
        return CacheEntry(
            fetch_count[],
            now_utc + Millisecond(1_000),
            now_utc + Millisecond(2_000),
        )
    end
    cache = SWRMemoryCache(fetcher)
    @test @inferred(cache_get!(cache)) == 1

    lock(cache.lock)
    try
        elapsed = @elapsed @test @inferred(cache_get!(cache)) == 1
        @test elapsed < 0.02
    finally
        unlock(cache.lock)
    end
end

@testitem "Default constructor infers cache value type when possible" begin
    using SWRCache
    using Test
    using Dates

    function fetcher()
        now_utc = now(UTC)
        return CacheEntry(
            42,
            now_utc + Millisecond(1_000),
            now_utc + Millisecond(2_000),
        )
    end
    cache = SWRMemoryCache(fetcher)
    @test @inferred(cache_get!(cache)) == 42
end
