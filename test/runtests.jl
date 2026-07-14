using SWRCache
using Test
using Base.Threads

@testset "SWRMemoryCache behavior" begin
    @testset "Fresh values are served without refresh" begin
        fetch_count = Ref(0)
        fetcher() = begin
            fetch_count[] += 1
            return "value-$(fetch_count[])"
        end
        cache = SWRMemoryCache(fetcher; options = RefreshOptions(ttl_seconds = 0.5, stale_ttl_seconds = 0.5))

        first_value = cache_get!(cache)
        second_value = cache_get!(cache)

        @test first_value == second_value
        @test fetch_count[] == 1
    end

    @testset "Stale reads are non-blocking and refresh in background with single-flight" begin
        fetch_count = Ref(0)
        fetcher() = begin
            fetch_count[] += 1
            sleep(0.15)
            return fetch_count[]
        end
        cache = SWRMemoryCache(fetcher; options = RefreshOptions(ttl_seconds = 0.2, stale_ttl_seconds = 0.4))

        @test cache_get!(cache) == 1
        sleep(0.22)

        stale_elapsed = @elapsed stale_value = cache_get!(cache)
        @test stale_value == 1
        @test stale_elapsed < 0.08

        stale_tasks = [Threads.@spawn cache_get!(cache) for _ in 1:4]
        stale_results = fetch.(stale_tasks)
        @test all(==(1), stale_results)

        sleep(0.2)
        @test cache_get!(cache) == 2
        @test fetch_count[] == 2
    end

    @testset "Expired reads block and share a single refresh task" begin
        fetch_count = Ref(0)
        fetcher() = begin
            fetch_count[] += 1
            sleep(0.2)
            return "refresh-$(fetch_count[])"
        end
        cache = SWRMemoryCache(fetcher; options = RefreshOptions(ttl_seconds = 0.04, stale_ttl_seconds = 0.03))

        @test cache_get!(cache) == "refresh-1"
        sleep(0.1)

        elapsed = @elapsed begin
            t1 = Threads.@spawn cache_get!(cache)
            t2 = Threads.@spawn cache_get!(cache)
            @test fetch(t1) == "refresh-2"
            @test fetch(t2) == "refresh-2"
        end

        @test elapsed >= 0.18
        @test elapsed < 0.35
        @test fetch_count[] == 2
    end

    @testset "Manual invalidation and refresh API" begin
        fetch_count = Ref(0)
        fetcher() = begin
            fetch_count[] += 1
            return fetch_count[]
        end
        cache = SWRMemoryCache(fetcher; options = RefreshOptions(ttl_seconds = 0.5, stale_ttl_seconds = 0.5))

        @test cache_get!(cache) == 1
        @test invalidate!(cache)
        @test !invalidate!(cache)
        @test cache_get!(cache) == 2
        @test refresh!(cache) == 3
        clear!(cache)
        @test cache_get!(cache) == 4
    end
end
