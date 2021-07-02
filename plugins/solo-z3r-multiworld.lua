local plugin = {}

plugin.name = "Solo Z3R Multiworld"
plugin.author = "authorblues"

plugin.settings =
{
}

plugin.description =
[[
	Intended to work with seeds generated by Aerinon's Z3 DoorRandomizer fork. Untested with keydropshuffle and shopsanity, so those features currently may or may not work. (https://github.com/aerinon/ALttPDoorRandomizer)

	Create a multiworld randomizer seed and generate roms for all players. Put them all in the games/ folder, and the plugin will shuffle like normal, sending items between seeds when necessary.

	Special thanks to Aerinon for providing significant help to get this working. Thanks also to Ankou for helping me sort out weird SNES+Bizhawk issues.
]]

local this_player_id = -1

local rom_name_addr = 0x7FC0 -- 15 bytes
local outgoing_item_addr = 0x02D8
local outgoing_player_addr = 0xC098
local incoming_item_addr = 0xF4D2
local incoming_player_addr = 0xF4D3
local recv_count_addr = 0xF4F0 -- 2 bytes

local SRAM_DATA_START = 0xF000
local SRAM_DATA_SIZE = 0x3E4

local prev_sram_data = nil

local function get_game_mode()
	return mainmemory.read_s8(0x0010)
end

local function is_normal_gameplay()
	local g = get_game_mode()
	return g == 0x07 or g == 0x09 or g == 0x0B
end

-- takes an address and a delimiter as parameters
-- returns integer equivalent of BCD value and address following delimiter
local function read_BCD_to_delimiter(addr, stop)
	local result = 0
	for i = 1,20 do
		local value = memory.read_s8(addr, "CARTROM")
		if value == stop then break end
		result = (result * 10) + (value - 0x30)
		addr = addr + 1
	end

	return result, addr+1
end

local function get_sram_data()
	return mainmemory.readbyterange(SRAM_DATA_START, SRAM_DATA_SIZE)
end

-- returns sram changes as a consistent, serialized string
local function get_changes(old, new)
	local changes = {}
	for addr,oldvalue in pairs(old) do
		local diff = bit.bxor(oldvalue, new[addr])
		if diff ~= 0 then
			local cstr = string.format('%04x,%02x', addr, diff)
			table.insert(changes, cstr)
		end
	end
	return table.concat(changes, ';')
end

-- this assumes no values are anything other than primitive and
-- are guaranteed to have the same keys (this is not a general purpose function)
local function table_equal(t1, t2)
	for k,v1 in pairs(t1) do
		local v2 = t2[k]
		-- if there isn't a matching value or types differ
		if v2 == nil or type(v1) ~= type(v2) then
			return false
		end
		-- if the primitive values don't match
		if v1 ~= v2 then return false end
	end
	return true
end

local function add_item_if_unique(list, item)
	for _,v in ipairs(list) do
		if table_equal(v, item) then
			return false
		end
	end

	table.insert(list, item)
	return true
end

function plugin.on_setup(data, settings)
	data.itemqueues = data.itemqueues or {}
	data.queuedsend = data.queuedsend or {}
end

function plugin.on_game_load(data, settings)
	--this_player_id = tonumber(get_current_game():match("_P(%d+)_"))
	local version, team_id = 0, 0
	local addr = rom_name_addr + 2

	version, addr = read_BCD_to_delimiter(addr, 0x5F)
	team_id, addr = read_BCD_to_delimiter(addr, 0x5F)
	this_player_id = read_BCD_to_delimiter(addr, 0x5F)

	data.itemqueues[this_player_id] = data.itemqueues[this_player_id] or {}
	data.queuedsend[this_player_id] = data.queuedsend[this_player_id] or {}
	prev_sram_data = get_sram_data()
end

function plugin.on_frame(data, settings)
	local player_id, item_id
	local sram_data = get_sram_data()

	if is_normal_gameplay() then
		player_id = mainmemory.read_s8(outgoing_player_addr)
		item_id = mainmemory.read_s8(outgoing_item_addr)

		local prev_player = data.prev_player or 0
		data.prev_player = player_id

		if player_id ~= 0 and prev_player == 0 then
			table.insert(data.queuedsend[this_player_id], {item=item_id, src=this_player_id, target=player_id})
			mainmemory.write_s8(outgoing_player_addr, 0)
			data.prev_player = 0
		end

		local queue_len = #data.itemqueues[this_player_id]
		local recv_count = mainmemory.read_s16_le(recv_count_addr)
		if mainmemory.read_s16_le(recv_count_addr) > queue_len then
			mainmemory.write_s16_le(recv_count_addr, 0)
			recv_count = 0
		end

		if recv_count < queue_len and mainmemory.read_s8(incoming_item_addr) == 0 then
			local obj = data.itemqueues[this_player_id][recv_count+1]
			mainmemory.write_s8(incoming_item_addr, obj.item)
			mainmemory.write_s8(incoming_player_addr, obj.player)
			mainmemory.write_s16_le(recv_count_addr, recv_count+1)
		end
	elseif get_game_mode() == 0x00 then
		-- if we somehow got to the title screen (reset?) with items queued to
		-- be sent, but we never saw the sram changes, the player was very
		-- naughty and tried to create a race condition. very naughty! bad player!
		data.queuedsend[this_player_id] = {}
	end

	-- when SRAM changes arrive and there are items queued to be sent, match them up
	local changes = get_changes(prev_sram_data, sram_data)
	if #data.queuedsend[this_player_id] > 0 and #changes > 0 then
		local item = table.remove(data.queuedsend[this_player_id], 1)
		item.meta = changes -- add the sram changes to the object to identify repeats
		data.itemqueues[item.target] = data.itemqueues[item.target] or {}
		add_item_if_unique(data.itemqueues[item.target], item)
	end

	prev_sram_data = sram_data
end

return plugin
