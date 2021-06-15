--[[
	To use this plugin, add an underscore to the end of the rom's filename,
	followed by a hex color code (before the file extension). A filter will be
	added over the game feed of the designated color.

	Color codes supported in RRGGBB or AARRGGBB format. If no alpha channel
	specified, the value provided via the settings window will be used instead.
	RRGGBB is the preferred format.

	EXAMPLE: Mega Man 4 (U)_00FF00.nes
	Naming the rom as shown above will color the screen green
--]]

local plugin = {}

plugin.name = "Color Filter"
plugin.author = "authorblues"
plugin.minversion = "2.6.2"
plugin.settings =
{
	{ name='opacity', type='number', label='Opacity (0-100)', default=15 },
	{ name='autocolor', type='boolean', label='Auto-assign colors for games missing hex codes' },
}

local DEFAULT_COLORS =
{
	'FF0000', '00FF00', '0000FF', '00FFFF', 'FF00FF', 'FFFF00',
	'00FF80', '0080FF', 'FF0080', '8000FF', 'FF8000', '80FF00',
}

local fillcolor

function plugin.on_setup(data, settings)
	-- normalize opacity setting
	settings.opacity = math.max(0, math.min(100, settings.opacity))

	-- setup colors table
	data.colors = {}
	data.colors._ndx = 0
end

function plugin.on_game_load(data, settings)
	fillcolor = data.colors[get_current_game()] or 0
	if not fillcolor then
		local colorhex, opacity

		-- find hex color from ROM filename
		for match in get_current_game():gmatch('_([0-9a-fA-F]+)') do
			if #match == 6 then colorhex = match end
		end

		-- if no color name was found, select from a list of default colors
		if colorhex == nil and settings.autocolor then
			data.colors._ndx = (data.colors._ndx % #DEFAULT_COLORS) + 1
			colorhex = DEFAULT_COLORS[data.colors._ndx]
		end

		if colorhex ~= nil then
			fillcolor = tonumber(colorhex, 16)
			if #colorhex == 6 then
				local alpha = bit.lshift(settings.opacity * 255 / 100, 24)
				fillcolor = fillcolor + alpha
			end
		end

		data.colors[get_current_game()] = fillcolor
	end
end

function plugin.on_frame(data, settings)
	gui.clearGraphics()
	gui.drawBox(0, 0, client.screenwidth(), client.screenheight(), 0, fillcolor, "client")
end

return plugin
