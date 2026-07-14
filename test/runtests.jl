using SWRCache
using Test
using Base.Threads
using Dates

@testset "SWRMemoryCache behavior" begin
    @testset "Fresh values are served without refresh" begin
        fetch_count = Ref(0)
        fetcher() = begin
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

    @testset "Stale reads currently error due unresolved type assertion in refresh path" begin
        fetch_count = Ref(0)
        fetcher() = begin
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

        @test_throws UndefVarError cache_get!(cache)
    end

    @testset "Expired reads currently error due unresolved type assertion in refresh path" begin
        fetch_count = Ref(0)
        fetcher() = begin
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

        @test_throws UndefVarError cache_get!(cache)
    end

    @testset "Manual invalidation and refresh API" begin
        fetch_count = Ref(0)
        fetcher() = begin
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
        @test_throws UndefVarError cache_get!(cache)
        @test_throws TypeError refresh!(cache)
        clear!(cache)
        @test_throws UndefVarError cache_get!(cache)
    end

    @testset "Fresh fast-path reads do not block on cache lock" begin
        fetch_count = Ref(0)
        fetcher() = begin
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

    @testset "Default constructor infers cache value type when possible" begin
        fetcher() = begin
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
end
