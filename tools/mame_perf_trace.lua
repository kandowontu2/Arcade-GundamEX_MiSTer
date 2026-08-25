local frame = 0
local totals = {
    rom = 0, extra_rom = 0, work = 0, extra_palette_read = 0,
    extra_palette_write = 0, sprite_write = 0, palette_write = 0,
    x1_write = 0
}
local window = {}
for name, _ in pairs(totals) do window[name] = 0 end

local cpu = manager.machine.devices[':maincpu']
local space = cpu.spaces['program']
local output = assert(io.open('gundamex_perf_trace.txt', 'w'))
local taps = {}

local function tap_read(first, last, name)
    taps[#taps + 1] = space:install_read_tap(first, last, name,
        function(offset, data, mask)
            totals[name] = totals[name] + 1
            window[name] = window[name] + 1
        end)
end

local function tap_write(first, last, name)
    taps[#taps + 1] = space:install_write_tap(first, last, name,
        function(offset, data, mask)
            totals[name] = totals[name] + 1
            window[name] = window[name] + 1
        end)
end

local function install_taps()
    cpu = manager.machine.devices[':maincpu']
    space = cpu.spaces['program']
    taps = {}
    tap_read(0x000000, 0x1fffff, 'rom')
    tap_read(0x500000, 0x57ffff, 'extra_rom')
    tap_read(0x200000, 0x20ffff, 'work')
    tap_read(0xc50000, 0xc5ffff, 'extra_palette_read')
    tap_write(0xc50000, 0xc5ffff, 'extra_palette_write')
    tap_write(0xc00000, 0xc3ffff, 'sprite_write')
    tap_write(0xc40000, 0xc4ffff, 'palette_write')
    tap_write(0xb00000, 0xb03fff, 'x1_write')
end

install_taps()
emu.add_machine_reset_notifier(function()
    install_taps()
end)

local function active_pcm_voices()
    local active = 0
    for voice = 0, 15 do
        local status = space:read_u16(0xb00000 + voice * 16) & 0xff
        if (status & 1) ~= 0 and (status & 2) == 0 then active = active + 1 end
    end
    return active
end

emu.register_frame_done(function()
    frame = frame + 1
    if frame % 60 == 0 then
        output:write(string.format(
            '%d rom=%d extra_rom=%d work=%d c5r=%d c5w=%d sprw=%d palw=%d x1w=%d pcm=%d\n',
            frame, window.rom, window.extra_rom, window.work,
            window.extra_palette_read, window.extra_palette_write,
            window.sprite_write, window.palette_write, window.x1_write,
            active_pcm_voices()))
        output:flush()
        for name, _ in pairs(window) do window[name] = 0 end
    end
    if frame == 7200 then
        output:write('TOTAL')
        for name, value in pairs(totals) do
            output:write(' ', name, '=', value)
        end
        output:write('\n')
        output:close()
        manager.machine:exit()
    end
end, 'gundamex_perf_trace')
