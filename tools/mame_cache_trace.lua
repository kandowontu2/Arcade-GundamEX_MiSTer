local frame = 0
local cpu = manager.machine.devices[':maincpu']
local space = cpu.spaces['program']
local output = assert(io.open('gundamex_cache_trace.txt', 'w'))
local tap

local configs = { 4, 16, 64, 128, 256 }
local caches = {}
for _, lines in ipairs(configs) do
    caches[lines] = { tags = {}, hits = 0, misses = 0 }
end

local function clear_caches()
    for _, lines in ipairs(configs) do
        caches[lines].tags = {}
        caches[lines].hits = 0
        caches[lines].misses = 0
    end
end

local function install_tap()
    cpu = manager.machine.devices[':maincpu']
    space = cpu.spaces['program']
    clear_caches()
    tap = space:install_read_tap(0x000000, 0x1fffff, 'rom_cache_trace',
        function(offset, data, mask)
            local line = offset >> 5
            for _, lines in ipairs(configs) do
                local index = line & (lines - 1)
                local tag = line >> math.floor(math.log(lines, 2))
                local cache = caches[lines]
                if cache.tags[index] == tag then
                    cache.hits = cache.hits + 1
                else
                    cache.misses = cache.misses + 1
                    cache.tags[index] = tag
                end
            end
        end)
end

install_tap()
emu.add_machine_reset_notifier(install_tap)

emu.register_frame_done(function()
    frame = frame + 1
    if frame % 600 == 0 then
        output:write(string.format('frame=%d', frame))
        for _, lines in ipairs(configs) do
            local cache = caches[lines]
            local total = cache.hits + cache.misses
            output:write(string.format(' lines%d=%d/%d(%.2f%%)', lines,
                cache.hits, total, 100.0 * cache.hits / total))
        end
        output:write('\n')
        output:flush()
    end
    if frame == 7200 then
        output:close()
        manager.machine:exit()
    end
end, 'gundamex_cache_trace')
