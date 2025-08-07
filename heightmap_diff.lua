--[[
OpenTTD Heightmap Diff, v1.0.0 (2025-08-04)
Author: chujo

License: CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)
You may use, modify, and distribute this script for non-commercial purposes only (attribution required).
Any modifications or derivative works must be licensed under the same terms.

This Lua script uses the IM library (from https://www.tecgraf.puc-rio.br/im/) to compare heightmap
images from OpenTTD (presumably one taken at the beginning of a game and another at the end)
and exports a PNG image with highlighted changes in terrain (raised land vs lowered land).

Simple statistics are printed out and can be saved into a TXT file.
-----------------------------------------------------------------------------------------------------------]]


----------------------------
-- VARIABLES AND SETTINGS --
----------------------------
-- Default values
table_of_input_filenames = {}
output_filename = nil
raised_color    = {0, 255, 0}
lowered_color   = {255, 0, 0}
save_stats      = true
-- Keywords for optional parameters
help_strings    = {"help", "-h", "--help"}
output_strings  = {"o", "output"}
raised_strings  = {"hi", "high"}
lowered_strings = {"lo", "low"}
stats_strings   = {"stats", "statistics"}


-----------------------
-- UTILITY FUNCTIONS --
----------------------- 
function error_msg(text)
    print("Error: " .. text)
    os.exit(1)
end
function containsAny(tbl, values)
    -- Check a table for membership of any item from a list
    for _, v in ipairs(tbl) do
        for _, target in ipairs(values) do
            if string.upper(v) == string.upper(target) then
                return true
            end
        end
    end
    return false
end
function help_msg()
    local function format_keywords(keywords, value_hint)
        local formatted = {}
        for _, key in ipairs(keywords) do
            local suffix = value_hint and "=" .. value_hint or ""
            table.insert(formatted, key .. suffix)
        end
        return table.concat(formatted, ", ")
    end

    local function color_to_string(color)
        return table.concat(color, ",")
    end

    local help_text = [[

  Usage: lua %s <input1> <input2> [options]
  
  Positional Arguments:
    input1                  First heightmap screenshot filename (e.g. start.png).
    input2                  Second heightmap screenshot filename (e.g. end.png).
  
  Optional Arguments:
    %s
                            Output filename (extension can be omitted, always PNG).
                            Generated automatically, if not specified.
  
    %s
                            RGB color for raised land.
                            Format: R,G,B or (R,G,B). Default: %s
  
    %s
                            RGB color for lowered land.
                            Format: R,G,B or (R,G,B). Default: %s
  
    %s
                            Whether to save statistical output into a TXT file.
                            Filename taken from <output>. Default: %s
  
    %s
                            Show this help message and exit.
    

    Examples:
      lua %s example/start.png end.png
          -- Run the comparison with default settings.
          -- 'start.png' in subfolder 'example'.

      lua %s start.png end.png o=diff
          -- Save output to 'diff.png' and statistics to 'diff.txt'.

      lua %s start.png end.png high=(0,255,255) low=255,100,100
          -- Customize raised and lowered land colors.

      lua %s start.png end.png statistics=false
          -- Disable saving of statistics.
    ]]

    local help_text_filled = string.format(
        help_text,
        arg[0],
        format_keywords(output_strings, "<output>"),
        format_keywords(raised_strings, "<R,G,B>"), color_to_string(raised_color),
        format_keywords(lowered_strings, "<R,G,B>"), color_to_string(lowered_color),
        format_keywords(stats_strings, "<true|false>"), tostring(save_stats),
        format_keywords(help_strings),
        arg[0],
        arg[0],
        arg[0],
        arg[0]
    )

    print(help_text_filled)
    os.exit(1)
end
function parse_rgb(value)
    -- Extracts RGB values from "R,G,B" or "(R,G,B)", returns them in a table
    local r, g, b = value:match("^%(?(%d+),(%d+),(%d+)%)?$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if r and g and b and r <= 255 and g <= 255 and b <= 255 then
        return {r, g, b}
    else
        return nil
    end
end
function str_to_bool(str)
    -- Convert boolean-like strings into proper boolean values
    if string.upper(str) == "FALSE" or string.upper(str) == "NO" then
        return false
    else
        return true
    end
end


-------------------------
-- PARSE CLI ARGUMENTS --
-------------------------
-- Parse input filenames
if not arg[1] or not arg[2] then
    help_msg()
else
	table_of_input_filenames = {
		arg[1],
		arg[2]
	}
end

-- Parse HELP
if containsAny(arg, help_strings) then
	help_msg()
end

-- Parse optional arguments (must use a keyword)
for i = 3, #arg do
    local key, value = string.match(arg[i], "^(%w+)%=(.+)$")
    if containsAny(output_strings, {key}) then
        output_filename = value:match("^(.*)%.[^%.]+$")

    elseif containsAny(raised_strings, {key}) then
        local rgb = parse_rgb(value)
        if rgb then
            raised_color = rgb
        else
            print("\nInvalid color format for raised land. Expected R,G,B or (R,G,B) with values 0-255.")
            os.exit(1)
        end

    elseif containsAny(lowered_strings, {key}) then
        local rgb = parse_rgb(value)
        if rgb then
            lowered_color = rgb
        else
            print("\nInvalid color format for lowered land. Expected R,G,B or (R,G,B) with values 0-255.")
            os.exit(1)
        end

    elseif containsAny(stats_strings, {key}) then
    	save_stats = str_to_bool(value)

    end
end


---------------------
-- LOAD IMAGE DATA --
---------------------
local ok, im = pcall(require, "imlua")
if not ok then error_msg("The 'imlua' module is missing or could not be loaded.") end

local table_of_image_data = {}
local width, height = nil, nil

for _, image_filename in ipairs(table_of_input_filenames) do
	local image = im.FileImageLoad(image_filename, im.IM_UNKNOWN)
	if not image then error_msg("Failed to load image: " .. image_filename) end

	-- Get image info, check whether dimensions match
	if width then
		if width ~= image:Width() or height ~= image:Height() then error_msg("Input images have different dimensions.") end
	else
		width, height = image:Width(), image:Height()
	end
	local color_space = image:ColorSpace()
	local data_type = image:DataType()

	-- Check if image is RGB or GRAY and IM_BYTE
	if color_space ~= im.RGB and color_space ~= im.GRAY then error_msg("Image '" .. image_filename .. "' is not in RGB or GRAY color space.") end
	if data_type ~= im.BYTE then error_msg("Image '" .. image_filename .. "' doesn't use IM_BYTE data type.") end

	table_of_image_data[image_filename] = {
		r = {},
		g = {},
		b = {}
	}

	for row = 0, height - 1 do
		for col = 0, width - 1 do
			if color_space == im.RGB then
				table.insert(table_of_image_data[image_filename].r, image[0][row][col])
				table.insert(table_of_image_data[image_filename].g, image[1][row][col])
				table.insert(table_of_image_data[image_filename].b, image[2][row][col])
			else
				table.insert(table_of_image_data[image_filename].r, image[0][row][col])
				table.insert(table_of_image_data[image_filename].g, image[0][row][col])
				table.insert(table_of_image_data[image_filename].b, image[0][row][col])
			end
		end
	end
end


----------------------
-- CREATE NEW IMAGE --
----------------------
-- Compare image data (only R channel, heightmaps are gray), put pixels into a new image
local new_image = im.ImageCreate(width, height, im.RGB, im.BYTE)

local counter_raised, counter_lowered = 0, 0
local i = 1

local img1 = table_of_image_data[table_of_input_filenames[1]]
local img2 = table_of_image_data[table_of_input_filenames[2]]

local r_raised, g_raised, b_raised    = table.unpack(raised_color)
local r_lowered, g_lowered, b_lowered = table.unpack(lowered_color)

for row = 0, height - 1 do
	for col = 0, width - 1 do
		if img1.r[i] == img2.r[i] then
			new_image[0][row][col] = img1.r[i]
			new_image[1][row][col] = img1.g[i]
			new_image[2][row][col] = img1.b[i]
		elseif img2.r[i] > img1.r[i] then
			new_image[0][row][col] = r_raised
			new_image[1][row][col] = g_raised
			new_image[2][row][col] = b_raised
			counter_raised = counter_raised + 1
		elseif img2.r[i] < img1.r[i] then
			new_image[0][row][col] = r_lowered
			new_image[1][row][col] = g_lowered
			new_image[2][row][col] = b_lowered
			counter_lowered = counter_lowered + 1
		end
		i = i + 1
	end
end

output_filename = output_filename or string.format("Raised-%d, lowered-%d", counter_raised, counter_lowered)
im.FileImageSave(output_filename .. ".png", "PNG", new_image)


----------------
-- STATISTICS --
----------------
local total_pixels = width * height
local unchanged = total_pixels - (counter_raised + counter_lowered)

function to_percent(n) return string.format("%.2f", (n / total_pixels) * 100) end
local statistics = [[
Summary:
--------
Total tiles     : ]] .. string.format("%d", total_pixels) .. [[ 
Changed tiles   : ]] .. string.format("%d", counter_raised + counter_lowered) .. " (" .. to_percent(counter_raised + counter_lowered) .. [[ %)
 - raised land  : ]] .. counter_raised .. " (" .. to_percent(counter_raised) .. [[ %)
 - lowered land : ]] .. counter_lowered .. " (" .. to_percent(counter_lowered) .. [[ %)
Unchanged tiles : ]] .. string.format("%d", unchanged) .. " (" .. to_percent(unchanged) .. [[ %)]]

print("")
print(statistics)
print('\nOutput saved as : "' .. output_filename .. '.png"')

if save_stats == true then
	local stats_file, err = io.open(output_filename .. ".txt", "w")
	if not stats_file then
			error("Error: Could not create file: " .. output_filename .. ".txt\nError: " .. err .. "\n")
	end
	stats_file:write(statistics)
	stats_file:close()
    print('Stats saved as  : "' .. output_filename .. '.txt"')
end