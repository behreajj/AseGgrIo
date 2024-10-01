local defaults <const> = {
    samples = 32,
    showExportOptions = false,
    blendFunc = "LINEAR",
    colorSpace = "SRGB"
}

---@param aseColor Color
---@return string
local function aseColorToGgrString(aseColor)
    return string.format(
        "%.6f %.6f %.6f %.6f",
        aseColor.red / 255.0,
        aseColor.green / 255.0,
        aseColor.blue / 255.0,
        aseColor.alpha / 255.0)
end

---@param hue number
---@param sat number
---@param val number
---@return number
---@return number
---@return number
local function hsbToRgb(hue, sat, val)
    local h <const> = (hue % 1.0) * 6.0
    local s <const> = math.min(math.max(sat, 0.0), 1.0)
    local v <const> = math.min(math.max(val, 0.0), 1.0)

    local sector <const> = math.floor(h)
    local secf <const> = sector + 0.0
    local tint1 <const> = v * (1.0 - s)
    local tint2 <const> = v * (1.0 - s * (h - secf))
    local tint3 <const> = v * (1.0 - s * (1.0 + secf - h))

    if sector == 0 then
        return v, tint3, tint1
    elseif sector == 1 then
        return tint2, v, tint1
    elseif sector == 2 then
        return tint1, v, tint3
    elseif sector == 3 then
        return tint1, tint2, v
    elseif sector == 4 then
        return tint3, tint1, v
    elseif sector == 5 then
        return v, tint1, tint2
    elseif sector == 6 then
        return v, tint3, tint1
    end

    return 0.0, 0.0, 0.0
end

---@param origin number
---@param dest number
---@param t number
---@param range number
---@return number
local function lerpAngleCw(origin, dest, t, range)
    local rangeVerif <const> = range or 1.0
    local o <const> = origin % rangeVerif
    local d <const> = dest % rangeVerif
    local diff <const> = d - o
    if diff == 0.0 then return d end

    local u <const> = 1.0 - t
    if o < d then
        return (u * (o + rangeVerif) + t * d) % rangeVerif
    else
        return u * o + t * d
    end
end

---@param origin number
---@param dest number
---@param t number
---@param range number
---@return number
local function lerpAngleCcw(origin, dest, t, range)
    local rangeVerif <const> = range or 360.0
    local o <const> = origin % rangeVerif
    local d <const> = dest % rangeVerif
    local diff <const> = d - o
    if diff == 0.0 then return o end

    local u <const> = 1.0 - t
    if o > d then
        return (u * o + t * (d + rangeVerif)) % rangeVerif
    else
        return u * o + t * d
    end
end

---@param shades Color[]
---@param fac number
---@return integer r
---@return integer g
---@return integer b
---@return integer a
local function mixShades(shades, fac)
    if fac <= 0.0 then
        local aseColor <const> = shades[1]
        if aseColor.alpha > 0 then
            return aseColor.red,
                aseColor.green,
                aseColor.blue,
                aseColor.alpha
        end
    elseif fac >= 1.0 then
        local aseColor <const> = shades[#shades]
        if aseColor.alpha > 0 then
            return aseColor.red,
                aseColor.green,
                aseColor.blue,
                aseColor.alpha
        end
    else
        local tScaled <const> = fac * (#shades - 1)
        local i <const> = math.floor(tScaled)
        local t <const> = tScaled - i
        local u <const> = 1.0 - t
        local origColor <const> = shades[1 + i]
        local destColor <const> = shades[2 + i]

        local aOrig <const> = origColor.alpha
        local aDest <const> = destColor.alpha
        local ao01 <const> = aOrig / 255.0
        local ad01 <const> = aDest / 255.0
        local ac01 <const> = u * ao01 + t * ad01
        local ac255 <const> = math.floor(ac01 * 255 + 0.5)

        if ac255 > 0 then
            local rOrig <const> = origColor.red
            local gOrig <const> = origColor.green
            local bOrig <const> = origColor.blue

            local rDest <const> = destColor.red
            local gDest <const> = destColor.green
            local bDest <const> = destColor.blue

            local ro01 <const> = rOrig / 255.0
            local go01 <const> = gOrig / 255.0
            local bo01 <const> = bOrig / 255.0

            local rd01 <const> = rDest / 255.0
            local gd01 <const> = gDest / 255.0
            local bd01 <const> = bDest / 255.0

            local rc01 <const> = u * ro01 + t * rd01
            local gc01 <const> = u * go01 + t * gd01
            local bc01 <const> = u * bo01 + t * bd01

            local rc255 <const> = math.floor(rc01 * 255 + 0.5)
            local gc255 <const> = math.floor(gc01 * 255 + 0.5)
            local bc255 <const> = math.floor(bc01 * 255 + 0.5)

            return rc255, gc255, bc255, ac255
        end
    end
    return 0, 0, 0, 0
end

---@generic T element
---@param t T[]
---@return T[]
local function reverseTable(t)
    local n = #t
    local i = 1
    while i < n do
        t[i], t[n] = t[n], t[i]
        i = i + 1
        n = n - 1
    end
    return t
end

---@param red number
---@param green number
---@param blue number
---@return number
---@return number
---@return number
local function rgbToHsb(red, green, blue)
    local r <const> = math.min(math.max(red, 0.0), 1.0)
    local g <const> = math.min(math.max(green, 0.0), 1.0)
    local b <const> = math.min(math.max(blue, 0.0), 1.0)

    local gbmx <const> = math.max(g, b)
    local gbmn <const> = math.min(g, b)
    local mx <const> = math.max(r, gbmx)

    if mx < 0.003922 then return 0.0, 0.0, 0.0 end

    local mn <const> = math.min(r, gbmn)
    local diff <const> = mx - mn

    if diff < 0.003922 then
        local light <const> = (mx + mn) * 0.5
        if light > 0.960784 then
            return 0.0, 0.0, 1.0
        end
        return 0.0, 0.0, mx
    end

    local hue = 0.0
    if r == mx then
        hue = (g - b) / diff
        if g < b then hue = hue + 6.0 end
    elseif g == mx then
        hue = 2.0 + (b - r) / diff
    elseif b == mx then
        hue = 4.0 + (r - g) / diff
    end

    return hue / 6.0, diff / mx, mx
end

local dlg <const> = Dialog { title = "Gradient Import Export" }

dlg:shades {
    id = "shades",
    label = "Colors:",
    mode = "sort",
    colors = {}
}

dlg:button {
    id = "fromPalette",
    text = "&GET",
    label = "Palette:",
    focus = false,
    onclick = function()
        local sprite <const> = app.sprite

        if not sprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        local palIdx <const> = 1
        local spritePalettes <const> = sprite.palettes
        local palette <const> = spritePalettes[palIdx]

        ---@type Color[]
        local selectedColors <const> = {}

        ---@type integer[]
        local colorIndices = {}
        local range <const> = app.range
        if range.sprite == sprite then
            colorIndices = range.colors
        end
        local lenColorIndices <const> = #colorIndices

        if lenColorIndices > 0 then
            local i = 0
            while i < lenColorIndices do
                i = i + 1
                local colorIndex <const> = colorIndices[i]
                local aseColor <const> = palette:getColor(colorIndex)
                selectedColors[i] = aseColor
            end
        else
            local lenPalette <const> = #palette
            local j = 0
            while j < lenPalette do
                local aseColor <const> = palette:getColor(j)
                j = j + 1
                selectedColors[j] = aseColor
            end
        end

        dlg:modify { id = "shades", colors = selectedColors }
    end
}

dlg:button {
    id = "toPalette",
    text = "&SET",
    focus = false,
    onclick = function()
        local sprite <const> = app.sprite

        if not sprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local spriteSpec <const> = sprite.spec
        local colorMode <const> = spriteSpec.colorMode
        if colorMode == ColorMode.GRAY then
            app.alert {
                title = "Error",
                text = "Grayscale color mode not supported."
            }
            return
        end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        local args <const> = dlg.data
        local shades <const> = args.shades --[=[@as Color[]]=]
        local lenShades <const> = #shades

        if lenShades > 0 then
            local palIdx <const> = 1
            local spritePalettes <const> = sprite.palettes
            local palette <const> = spritePalettes[palIdx]

            app.transaction(function()
                if colorMode ~= ColorMode.RGB then
                    app.command.ChangePixelFormat { format = "rgb" }
                end

                ---@type integer[]
                local colorIndices = {}
                local range = app.range
                if range.sprite == sprite then
                    colorIndices = range.colors
                end
                local lenColorIndices <const> = #colorIndices

                if lenColorIndices > 0 then
                    local iToFac = 0.0
                    if lenColorIndices > 1 then
                        iToFac = 1.0 / (lenColorIndices - 1.0)
                    end
                    local i = 0
                    while i < lenColorIndices do
                        local fac <const> = i * iToFac
                        i = i + 1
                        local colorIndex <const> = colorIndices[i]
                        local rTrg <const>, gTrg <const>, bTrg <const>, aTrg <const> = mixShades(shades, fac)
                        local aseColor <const> = Color { r = rTrg, g = gTrg, b = bTrg, a = aTrg }
                        palette:setColor(colorIndex, aseColor)
                    end
                else
                    palette:resize(lenShades + 1)
                    palette:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
                    local i = 0
                    while i < lenShades do
                        i = i + 1
                        palette:setColor(i, shades[i])
                    end
                end

                if colorMode == ColorMode.INDEXED then
                    app.command.ChangePixelFormat {
                        format = "indexed",
                        dithering = "ordered"
                    }
                end
            end)

            app.refresh()
        end
    end
}

dlg:newrow { always = false }

dlg:button {
    id = "flip",
    text = "&FLIP",
    focus = false,
    onclick = function()
        local args <const> = dlg.data
        local shades <const> = args.shades --[=[@as Color[]]=]
        if #shades > 1 then
            dlg:modify {
                id = "shades",
                colors = reverseTable(shades)
            }
        end
    end
}

dlg:button {
    id = "clearShades",
    text = "C&LEAR",
    focus = false,
    onclick = function()
        dlg:modify { id = "shades", colors = {} }
    end
}

dlg:separator { id = "canvasSep" }

dlg:button {
    id = "canvasMap",
    label = "Canvas:",
    text = "&MAP",
    focus = false,
    onclick = function()
        local sprite <const> = app.sprite
        local layer <const> = app.layer
        local frame <const> = app.frame

        if not sprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local spriteSpec <const> = sprite.spec
        local colorMode <const> = spriteSpec.colorMode
        if colorMode == ColorMode.GRAY then
            app.alert {
                title = "Error",
                text = "Grayscale color mode not supported."
            }
            return
        end

        if not frame then
            app.alert {
                title = "Error",
                text = "There is no active frame."
            }
            return
        end

        if not layer then
            app.alert {
                title = "Error",
                text = "There is no active layer."
            }
            return
        end

        local cel <const> = layer:cel(frame)
        if not cel then
            app.alert {
                title = "Error",
                text = "There is no active cel."
            }
            return
        end

        if layer.isReference then
            app.alert {
                title = "Error",
                text = "Reference layers not supported."
            }
            return
        end

        if layer.isTilemap then
            app.alert {
                title = "Error",
                text = "Tilemap layers not supported."
            }
            return
        end

        local args <const> = dlg.data
        local shades <const> = args.shades --[=[@as Color[]]=]
        local lenShades <const> = #shades

        if lenShades < 2 then
            app.alert {
                title = "Error",
                text = "At least two colors required."
            }
            return
        end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        app.transaction(function()
            if colorMode ~= ColorMode.RGB then
                app.command.ChangePixelFormat { format = "rgb" }
            end

            local srcImg <const> = cel.image

            ---@type table<integer, boolean>
            local uniquesDict <const> = {}

            local srcItr <const> = srcImg:pixels()
            for srcPixel in srcItr do
                local srcHex <const> = srcPixel() --[[@as integer]]
                uniquesDict[srcHex] = true
            end

            local gamma <const> = 2.2
            local invGamma <const> = 1.0 / 2.2

            -- Cache methods used in loop.
            local pixelColor <const> = app.pixelColor
            local tDecompose <const> = pixelColor.rgbaA
            local bDecompose <const> = pixelColor.rgbaB
            local gDecompose <const> = pixelColor.rgbaG
            local rDecompose <const> = pixelColor.rgbaR
            local rgbaCompose <const> = pixelColor.rgba

            ---@type table<integer, integer>
            local srcToTrgDict <const> = {}
            for srcHex, _ in pairs(uniquesDict) do
                local trgHex = 0
                local srcAlpha <const> = tDecompose(srcHex)
                if srcAlpha > 0 then
                    local srcRed <const> = rDecompose(srcHex)
                    local srcGreen <const> = gDecompose(srcHex)
                    local srcBlue <const> = bDecompose(srcHex)

                    local r01 <const> = srcRed / 255.0
                    local g01 <const> = srcGreen / 255.0
                    local b01 <const> = srcBlue / 255.0

                    local rLin <const> = r01 ^ gamma
                    local gLin <const> = g01 ^ gamma
                    local bLin <const> = b01 ^ gamma

                    local y <const> = 0.2126 * rLin
                        + 0.7152 * gLin
                        + 0.0722 * bLin
                    local t <const> = y ^ invGamma

                    local rTrg <const>, gTrg <const>, bTrg <const>, aTrg <const> = mixShades(shades, t)
                    trgHex = rgbaCompose(rTrg, gTrg, bTrg, aTrg)
                end

                srcToTrgDict[srcHex] = trgHex
            end

            local trgImg <const> = srcImg:clone()
            local trgItr <const> = trgImg:pixels()
            for pixel in trgItr do
                pixel(srcToTrgDict[pixel()])
            end

            -- if not trgImg:isEmpty() then
            local mapLayer <const> = sprite:newLayer()
            mapLayer.name = "Map"
            sprite:newCel(mapLayer, frame, trgImg, cel.position)
            -- end

            if colorMode == ColorMode.INDEXED then
                app.command.ChangePixelFormat {
                    format = "indexed",
                    dithering = "ordered"
                }
            end
        end)

        app.refresh()
    end
}

dlg:separator { id = "importSep" }

dlg:slider {
    id = "samples",
    label = "Samples:",
    min = 3,
    max = 255,
    value = defaults.samples
}

dlg:newrow { always = false }

dlg:file {
    id = "importFilepath",
    label = "Open:",
    filetypes = { "ggr" },
    open = true,
    focus = true
}

dlg:newrow { always = false }

dlg:button {
    id = "import",
    text = "&IMPORT",
    focus = false,
    onclick = function()
        local args <const> = dlg.data
        local filepath <const> = args.importFilepath --[[@as string]]
        local samples <const> = args.samples or defaults.samples --[[@as integer]]

        if (not filepath) or (#filepath < 1) then
            app.alert {
                title = "Error",
                text = "Filepath is empty."
            }
            return
        end

        local fileExt <const> = string.lower(app.fs.fileExtension(filepath))
        if fileExt ~= "ggr" then
            app.alert {
                title = "Error",
                text = "File format is not ggr."
            }
            return
        end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        local file <const>, err <const> = io.open(filepath, "r")

        if file ~= nil then
            local strlower <const> = string.lower
            local strgmatch <const> = string.gmatch
            local strsub <const> = string.sub

            ---@type number[][]
            local keys <const> = {}

            local linesItr <const> = file:lines()
            for line in linesItr do
                local lc <const> = strlower(line)
                if lc == "gimp gradient" then
                    -- Skip header.
                elseif strsub(lc, 1, 1) == '#' then
                    -- Skip comments.
                elseif strsub(lc, 1, 4) == "name" then
                    -- Skip names.
                elseif #lc > 0 then
                    ---@type string[]
                    local tokens <const> = {}
                    local lenTokens = 0
                    for token in strgmatch(line, "%S+") do
                        lenTokens = lenTokens + 1
                        tokens[lenTokens] = token
                    end

                    if lenTokens > 12 then
                        ---@type number[]
                        local seg <const> = {}
                        local j = 0
                        while j < 13 do
                            j = j + 1
                            local parsed <const> = tonumber(tokens[j])
                            local value = 0
                            if parsed then value = parsed end
                            seg[j] = value
                        end
                        keys[#keys + 1] = seg
                    end
                end
            end

            -- Constants used in loop.
            local pi <const> = math.pi
            local halfPi <const> = pi * 0.5
            local logHalf <const> = -0.6931471805599453
            local one720 <const> = 1.0 / 720.0
            local one1080 <const> = 1.0 / 1080.0

            -- Methods used in loop.
            local abs <const> = math.abs
            local floor <const> = math.floor
            local log <const> = math.log
            local sin <const> = math.sin
            local sqrt <const> = math.sqrt
            local exp <const> = math.exp

            ---@type Color[]
            local parsedColors <const> = {}
            local lenKeys <const> = #keys
            local iToFac <const> = 1.0 / (samples - 1.0)
            local i = 0
            while i < samples do
                local iFac <const> = i * iToFac
                i = i + 1

                local r01 = 0.0
                local g01 = 0.0
                local b01 = 0.0
                local a01 = 0.0

                if iFac <= keys[1][1] then
                    -- If less than lower bound,
                    -- then set to left color of first key.
                    local seg <const> = keys[1]
                    r01 = seg[4]
                    g01 = seg[5]
                    b01 = seg[6]
                    a01 = seg[7]
                elseif iFac >= keys[lenKeys][3] then
                    -- If greater than upper bound,
                    -- then set to right color of last key.
                    local seg <const> = keys[lenKeys]
                    r01 = seg[8]
                    g01 = seg[9]
                    b01 = seg[10]
                    a01 = seg[11]
                else
                    -- Search for the segment within which the step falls.
                    local segFound = false
                    local seg = nil
                    local m = 0
                    repeat
                        m = m + 1
                        seg = keys[m]
                        segFound = seg[1] <= iFac and iFac <= seg[3]
                    until segFound or m >= lenKeys

                    -- Unpack weights for left, right and middle.
                    local segLft <const> = seg[1]
                    local segMid <const> = seg[2]
                    local segRgt <const> = seg[3]

                    -- Find normalized step.
                    local denom = 0.0
                    if segLft ~= segRgt then
                        denom = 1.0 / (segRgt - segLft)
                    end
                    local mid <const> = (segMid - segLft) * denom
                    local pos <const> = (iFac - segLft) * denom

                    -- https://github.com/GNOME/gimp/blob/master/app/core/gimpgradient.c#L2227
                    local localFac = 0.5
                    if pos <= mid then
                        if mid < 0.000001 then
                            localFac = 0.0
                        else
                            localFac = 0.5 * (pos / mid)
                        end
                    else
                        if (1.0 - mid) < 0.000001 then
                            localFac = 1.0
                        else
                            localFac = 0.5 + 0.5 * (pos - mid) / (1.0 - mid)
                        end
                    end

                    local blendFuncCode <const> = floor(seg[12])
                    if blendFuncCode == 1 then
                        -- Curved
                        if mid < 0.000001 then
                            localFac = 1.0
                        elseif 1.0 - mid < 0.000001 then
                            localFac = 0.0
                        else
                            localFac = exp(logHalf * log(pos) / log(mid))
                        end
                    elseif blendFuncCode == 2 then
                        -- Sine
                        localFac = 0.5 * (sin(pi * localFac - halfPi) + 1.0)
                    elseif blendFuncCode == 3 then
                        -- Sphere Increasing
                        localFac = sqrt(1.0 - (localFac - 1.0) ^ 2)
                    elseif blendFuncCode == 4 then
                        -- Sphere Decreasing
                        localFac = 1.0 - sqrt(1.0 - localFac ^ 2)
                    else
                        -- Linear
                    end

                    local r01Lft <const> = seg[4]
                    local g01Lft <const> = seg[5]
                    local b01Lft <const> = seg[6]
                    local a01Lft <const> = seg[7]

                    local r01Rgt <const> = seg[8]
                    local g01Rgt <const> = seg[9]
                    local b01Rgt <const> = seg[10]
                    local a01Rgt <const> = seg[11]

                    local colorSpaceCode <const> = floor(seg[13])
                    local isHsbCcw <const> = colorSpaceCode == 1
                    local isHsbCw <const> = colorSpaceCode == 2
                    local isHsb <const> = isHsbCcw or isHsbCw
                    local lftIsGray <const> = r01Lft == g01Lft
                        and g01Lft == b01Lft
                    local rgtIsGray <const> = r01Rgt == g01Rgt
                        and g01Rgt == b01Rgt
                    local isValidHsb <const> = not (lftIsGray or rgtIsGray)

                    if isHsb and isValidHsb then
                        -- HSB

                        -- Use custom conversions for better accuracy.
                        -- https://community.aseprite.org/t/problem-using-hsl-values/20130/
                        local hLft, sLft <const>, vLft <const> = rgbToHsb(r01Lft, g01Lft, b01Lft)
                        local hRgt <const>, sRgt <const>, vRgt <const> = rgbToHsb(r01Rgt, g01Rgt, b01Rgt)

                        local u <const> = 1.0 - localFac
                        local sTrg <const> = u * sLft + localFac * sRgt
                        local vTrg <const> = u * vLft + localFac * vRgt

                        local equalHues <const> = abs(hRgt - hLft) < one720
                        local hTrg = 0.0
                        if isHsbCcw then
                            if equalHues then
                                hLft = hLft + one1080
                            end
                            hTrg = lerpAngleCcw(hLft, hRgt, localFac, 1.0)
                        elseif isHsbCw then
                            if equalHues then
                                hLft = hLft - one1080
                            end
                            hTrg = lerpAngleCw(hLft, hRgt, localFac, 1.0)
                        end

                        r01, g01, b01 = hsbToRgb(hTrg, sTrg, vTrg)
                        a01 = u * a01Lft + localFac * a01Rgt
                    else
                        -- Standard RGB.
                        local u <const> = 1.0 - localFac
                        r01 = u * r01Lft + localFac * r01Rgt
                        g01 = u * g01Lft + localFac * g01Rgt
                        b01 = u * b01Lft + localFac * b01Rgt
                        a01 = u * a01Lft + localFac * a01Rgt
                    end
                end

                local aseColorTrg <const> = Color {
                    r = floor(r01 * 255 + 0.5),
                    g = floor(g01 * 255 + 0.5),
                    b = floor(b01 * 255 + 0.5),
                    a = floor(a01 * 255 + 0.5)
                }
                parsedColors[#parsedColors + 1] = aseColorTrg
            end

            dlg:modify { id = "shades", colors = parsedColors }
        end
    end
}

dlg:separator { id = "exportSep" }

dlg:combobox {
    id = "blendFunc",
    label = "Blend:",
    option = "LINEAR",
    options = { "CURVE", "LINEAR", "SINE", "SPHERE_DECR", "SPHERE_INCR" },
    visible = defaults.showExportOptions
}

dlg:newrow { always = false }

dlg:combobox {
    id = "colorSpace",
    label = "Space:",
    option = "SRGB",
    options = { "HSB_CCW", "HSB_CW", "SRGB" },
    visible = defaults.showExportOptions
}

dlg:newrow { always = false }

dlg:file {
    id = "exportFilepath",
    label = "Save:",
    filetypes = { "ggr" },
    save = true,
    focus = false
}

dlg:newrow { always = false }

dlg:button {
    id = "export",
    text = "&EXPORT",
    focus = false,
    onclick = function()
        local args <const> = dlg.data
        local filepath <const> = args.exportFilepath --[[@as string]]
        if (not filepath) or (#filepath < 1) then
            app.alert {
                title = "Error",
                text = "Filepath is empty."
            }
            return
        end

        local fileExt <const> = app.fs.fileExtension(filepath)
        if string.lower(fileExt) ~= "ggr" then
            app.alert {
                title = "Error",
                text = "Extension is not ggr."
            }
            return
        end

        local shades <const> = args.shades --[=[@as Color[]]=]
        local lenShades <const> = #shades
        if lenShades < 2 then
            app.alert {
                title = "Error",
                text = "At least two colors required."
            }
            return
        end

        -- As a precaution against crashes, do not allow slices UI interface
        -- to be active.
        local appTool <const> = app.tool
        if appTool then
            local toolName <const> = appTool.id
            if toolName == "slice" then
                app.tool = "hand"
            end
        end

        local blendFuncStr <const> = args.blendFunc
            or defaults.blendFunc --[[@as string]]
        local blendFuncCode = 0
        if blendFuncStr == "CURVE" then
            blendFuncCode = 1
        elseif blendFuncStr == "SINE" then
            blendFuncCode = 2
        elseif blendFuncStr == "SPHERE_INCR" then
            blendFuncCode = 3
        elseif blendFuncStr == "SPHERE_DECR" then
            blendFuncCode = 4
        end

        local colorSpaceStr <const> = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local colorSpaceCode = 0
        if colorSpaceStr == "HSB_CCW" then
            colorSpaceCode = 1
        elseif colorSpaceStr == "HSB_CW" then
            colorSpaceCode = 2
        end

        -- Each color key has a left edge (1), middle point (2) and right edge
        -- (3). Colors are placed on the left edge as red, green blue and alpha
        -- (4, 5, 6, 7) and on the right edge (8, 9, 10, 11). The easing
        -- function is encoded in column 12. The color space is in 13.

        ---@type string[]
        local headerStrs <const> = {
            "GIMP Gradient\n",
            string.format("Name: %s\n", app.fs.fileTitle(filepath)),
            string.format("%d\n", lenShades - 1)
        }

        local currClr = shades[1]
        local prevStep = 0.0
        local prevClrStr = aseColorToGgrString(currClr)

        local strfmt <const> = string.format

        ---@type string[]
        local segStrs <const> = {}

        local i = 1
        while i < lenShades do
            local currStep <const> = i / (lenShades - 1.0)
            i = i + 1
            currClr = shades[i]
            local currClrStr <const> = aseColorToGgrString(currClr)

            segStrs[i - 1] = strfmt(
                "%.6f %.6f %.6f %s %s %d %d",
                prevStep,
                (prevStep + currStep) * 0.5,
                currStep,
                prevClrStr,
                currClrStr,
                blendFuncCode,
                colorSpaceCode)

            prevStep = currStep
            prevClrStr = currClrStr
        end

        local ggrStr <const> = string.format(
            "%s%s",
            table.concat(headerStrs),
            table.concat(segStrs, "\n"))

        local file <const>, err <const> = io.open(filepath, "w")
        if file then
            file:write(ggrStr)
            file:close()
        end

        if err then
            app.alert { title = "Error", text = err }
            return
        end

        app.alert { title = "Success", text = "File exported." }
    end
}

dlg:separator { id = "cancelSep" }

dlg:button {
    id = "cancel",
    text = "&CANCEL",
    focus = false,
    onclick = function()
        dlg:close()
    end
}

dlg:show {
    autoscrollbars = true,
    wait = false
}