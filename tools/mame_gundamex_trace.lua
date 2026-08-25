local frame = 0
local trace
local vtap
local ttap
local htap
local headers = {}

local function hex(value, width)
    return string.format('%0' .. width .. 'X', value)
end

local function start_trace()
    local cpu = manager.machine.devices[':maincpu']
    local space = cpu.spaces['program']
    trace = assert(io.open('gundamex_register_trace.txt', 'w'))
    for tag, share in pairs(manager.machine.memory.shares) do
        trace:write('SHARE ', tag, ' size=', share.size,
            ' length=', share.length, ' bits=', share.bitwidth,
            ' endian=', share.endianness, '\n')
    end
    vtap = space:install_write_tap(0xc60000, 0xc6003f, 'gundamex_video',
        function(offset, data, mask)
            trace:write(frame, ' V ', hex(offset, 6), ' ',
                hex(data, 4), ' ', hex(mask, 4), '\n')
        end)
    ttap = space:install_write_tap(0xfffc80, 0xffffff, 'gundamex_tmp',
        function(offset, data, mask)
            trace:write(frame, ' T ', hex(offset, 6), ' ',
                hex(data, 4), ' ', hex(mask, 4), '\n')
        end)
    htap = space:install_write_tap(0xc03000, 0xc03fff, 'gundamex_headers',
        function(offset, data, mask)
            local old = headers[offset] or 0
            headers[offset] = (old & (~mask & 0xffff)) | (data & mask)
        end)
end

local function log_list()
    local descriptors = 0
    for index = 0, 511 do
        local word0 = headers[0xc03000 + index * 8] or 0
        descriptors = descriptors + (word0 & 0xff) + 1
        if (word0 & 0x8000) ~= 0 then
            trace:write(frame, ' LIST headers=', index + 1,
                ' descriptors=', descriptors, '\n')
            return
        end
    end
    trace:write(frame, ' LIST headers=512 descriptors=', descriptors,
        ' NO_END\n')
end

local function save_words(space, filename, first, last)
    local output = assert(io.open(filename, 'wb'))
    for address = first, last, 2 do
        output:write(string.pack('>I2', space:read_u16(address)))
    end
    output:close()
end

local function save_share(share, filename)
    local output = assert(io.open(filename, 'wb'))
    for offset = 0, share.size - share.bytewidth, share.bytewidth do
        output:write(string.pack('>I2', share:read_u16(offset)))
    end
    output:close()
end

start_trace()

local cpu_space = manager.machine.devices[':maincpu'].spaces['program']
local listtap = cpu_space:install_write_tap(0xc60026, 0xc60027,
    'gundamex_list_trigger', function(offset, data, mask)
        if (data & mask & 0xffff) ~= 0 then
            log_list()
        end
    end)

emu.register_frame_done(function()
    frame = frame + 1
    if frame == 3600 then
        local space = manager.machine.devices[':maincpu'].spaces['program']
        save_share(manager.machine.memory.shares[':video:spriteram'],
            'gundamex_spr.bin')
        save_share(manager.machine.memory.shares[':video:vregs'],
            'gundamex_vreg.bin')
        save_words(space, 'gundamex_tmp.bin', 0xfffc00, 0xffffff)
        trace:write('FINAL_FRAME ', frame, '\n')
        trace:close()
        manager.machine:exit()
    end
end, 'gundamex_trace')
