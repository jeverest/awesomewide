---------------------------------------------------------------------------
--- Tiled layouts module for awful
--
-- @author Donald Ephraim Curtis &lt;dcurtis@cs.uiowa.edu&gt;
-- @author Julien Danjou &lt;julien@danjou.info&gt;
-- @copyright 2009 Donald Ephraim Curtis
-- @copyright 2008 Julien Danjou
-- @module awful.layout
---------------------------------------------------------------------------

-- Grab environment we need
local tag     = require("awful.tag")
local client  = require("awful.client")
local ipairs  = ipairs
local math    = math
local capi =
{
    mouse = mouse,
    screen = screen,
    mousegrabber = mousegrabber
}

local centeredtile = {}

--- The tile layout layoutbox icon.
-- @beautiful beautiful.layout_tile
-- @param surface
-- @see gears.surface

local function mouse_resize_handler(c, _, _, _)
    local wa = c.screen.workarea
    local mwfact = c.screen.selected_tag.master_width_factor
    local cursor
    local g = c:geometry()
    local offset = 0
    local corner_coords

    cursor = "cross"
    if g.height+15 > wa.height then
        offset = g.height * .5
        cursor = "sb_h_double_arrow"
    elseif not (g.y+g.height+15 > wa.y+wa.height) then
        offset = g.height
    end

    corner_coords = { x = wa.x + wa.width * mwfact, y = g.y + offset }
    capi.mouse.coords(corner_coords)

    local prev_coords = {}
    capi.mousegrabber.run(function (_mouse)
                              if not c.valid then return false end

                              for _, v in ipairs(_mouse.buttons) do
                                  if v then
                                      prev_coords = { x =_mouse.x, y = _mouse.y }
                                      local fact_x = (_mouse.x - wa.x) / wa.width
                                      local fact_y = (_mouse.y - wa.y) / wa.height
                                      local new_mwfact

                                      local geom = c:geometry()

                                      -- we have to make sure we're not on the last visible
                                      -- client where we have to use different settings.
                                      local wfact
                                      local wfact_x, wfact_y
                                      if (geom.y+geom.height+15) > (wa.y+wa.height) then
                                          wfact_y = (geom.y + geom.height - _mouse.y) / wa.height
                                      else
                                          wfact_y = (_mouse.y - geom.y) / wa.height
                                      end

                                      if (geom.x+geom.width+15) > (wa.x+wa.width) then
                                          wfact_x = (geom.x + geom.width - _mouse.x) / wa.width
                                      else
                                          wfact_x = (_mouse.x - geom.x) / wa.width
                                      end

                                      new_mwfact = fact_x
                                      wfact = wfact_y

                                      c.screen.selected_tag.master_width_factor
                                        = math.min(math.max(new_mwfact, 0.01), 0.99)
                                      client.setwfact(math.min(math.max(wfact,0.01), 0.99), c)
                                      return true
                                  end
                              end
                              return prev_coords.x == _mouse.x and prev_coords.y == _mouse.y
                          end, cursor)
end

local function apply_size_hints(c, width, height, useless_gap)
    local bw = c.border_width
    width, height = width - 2 * bw - useless_gap, height - 2 * bw - useless_gap
    width, height = c:apply_size_hints(math.max(1, width), math.max(1, height))
    return width + 2 * bw + useless_gap, height + 2 * bw + useless_gap
end

local function tile_group(gs, cls, wa, fact, group, useless_gap)
    local height = "height"
    local width = "width"
    local x = "x"
    local y = "y"

    -- make this more generic (not just width)
    local available = wa[width] - (group.coord - wa[x])
    -- find our total values
    local total_fact = 0
    local min_fact = 1
    local size = group.size
    for c = group.first,group.last do
        -- determine the width/height based on the size_hint
        local i = c - group.first +1
        local size_hints = cls[c].size_hints
        local size_hint = size_hints["min_"..width] or size_hints["base_"..width] or 0
        size = math.max(size_hint, size)

        -- calculate the height
        if not fact[i] then
            fact[i] = min_fact
        else
            min_fact = math.min(fact[i],min_fact)
        end
        total_fact = total_fact + fact[i]
    end
    size = math.max(1, math.min(size, available))

    local coord = wa[y]
    local used_size = 0
    local unused = wa[height]
    for c = group.first,group.last do
        local geom = {}
        local hints = {}
        local i = c - group.first +1
        geom[width] = size
        geom[height] = math.max(1, math.floor(unused * fact[i] / total_fact))
        geom[x] = group.coord
        geom[y] = coord
        gs[cls[c]] = geom
        hints.width, hints.height = apply_size_hints(cls[c], geom.width, geom.height, useless_gap)
        coord = coord + hints[height]
        unused = unused - hints[height]
        total_fact = total_fact - fact[i]
        used_size = math.max(used_size, hints[width])
    end

    return used_size
end

local function do_tile(param)
    local t = param.tag or capi.screen[param.screen].selected_tag
    local width = "width"
    local x = "x"

    local gs = param.geometries
    local cls = param.clients
    local useless_gap = param.useless_gap
    local nmaster = math.min(t.master_count, #cls)
    local mwfact = t.master_width_factor
    local wa = param.workarea
    local wmaster = math.floor(wa[width] * mwfact)
    local ncol = t.column_count
    local wslaves = math.floor((wa[width] - wmaster) / ncol)

    local data = tag.getdata(t).windowfact
    if not data then
        data = {}
        tag.getdata(t).windowfact = data
    end

    -- Add the master in the middle or 1 slave width from the left
    if not data[0] then
        data[0] = {}
    end
    local size = math.min(wa[width] * mwfact, wa[width])
    local coord = wa[x] + wslaves
    tile_group(gs, cls, wa, data[0], {first=1, last=nmaster, coord = coord, size = size}, useless_gap)

    -- no more clients to place
    if #cls <= 1 then return end

    -- Add the remaining cols left to right skipping the master in the "second col" or "middle"
    local last = nmaster
    local size = wslaves
    coord = wa[x]
    for i = 1,ncol do
        if (#cls - last) == 0 then return end  -- ran out of clients, don't place an empty col

        -- grab next set of cls in this col
        -- tile the column and update our current x coordinate
        local first = last + 1
        last = math.max(last + math.floor((#cls - last)/(ncol -i + 1)), first)
        if not data[i] then
            data[i] = {}
        end
        coord = coord + tile_group(gs, cls, wa, data[i], { first = first, last = last, coord = coord, size = size }, useless_gap)

        -- skip over master since that is already placed.
        if i == 1 then
            coord = coord + wmaster
        end
   end
end

function centeredtile.skip_gap(nclients, t)
    return nclients == 1 and t.master_fill_policy == "expand"
end

--- The main tile algo, on the right.
-- @param screen The screen number to tile.
-- @clientlayout awful.layout.suit.centeredtile.right
centeredtile.right = {}
centeredtile.right.name = "centeredtile"
centeredtile.right.arrange = do_tile
centeredtile.right.skip_gap = centeredtile.skip_gap
function centeredtile.right.mouse_resize_handler(c, corner, x, y)
    return mouse_resize_handler(c, corner, x, y)
end

centeredtile.arrange = centeredtile.right.arrange
centeredtile.mouse_resize_handler = centeredtile.right.mouse_resize_handler
centeredtile.name = centeredtile.right.name

return centeredtile





--[[
local naughty = require("naughty") -- debug
naughty.notify({text = "mouse_resize_handler"})
naughty.notify({text = "tile_group:" .. "gs" .. tostring(gs) .. " cls-".. tostring(cls) .. " wa-" .. tostring(wa) .. " used_size-" .. tostring(used_size)})
naughty.notify({text = "here"})
naughty.notify({text = "[do_tile master]" .. " coord=" .. tostring(coord) .. " size=".. tostring(size) .. " nmaster" .. tostring(nmaster) .. " test-" .. tostring(ncol)})
naughty.notify({text = "[do_tile slaves]" .. " first=" .. tostring(first) .. " last=".. tostring(last) .. " col i-" .. tostring(i) .. " test-" .. tostring(coord)})
--]]
