local defaults = {
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

---@param shades Color[]
---@param fac number
---@return integer r
---@return integer g
---@return integer b
---@return integer a
local function mixShades(shades, fac)
    if fac <= 0.0 then
        local aseColor = shades[1]
        if aseColor.alpha > 0 then
            return aseColor.red,
                aseColor.green,
                aseColor.blue,
                aseColor.alpha
        end
    elseif fac >= 1.0 then
        local aseColor = shades[#shades]
        if aseColor.alpha > 0 then
            return aseColor.red,
                aseColor.green,
                aseColor.blue,
                aseColor.alpha
        end
    else
        local tScaled = fac * (#shades - 1)
        local i = math.floor(tScaled)
        local t = tScaled - i
        local u = 1.0 - t
        local origColor = shades[1 + i]
        local destColor = shades[2 + i]

        local aOrig = origColor.alpha
        local aDest = destColor.alpha
        local ao01 = aOrig / 255.0
        local ad01 = aDest / 255.0
        local ac01 = u * ao01 + t * ad01
        local ac255 = math.floor(ac01 * 255 + 0.5)

        if ac255 > 0 then
            local rOrig = origColor.red
            local gOrig = origColor.green
            local bOrig = origColor.blue

            local rDest = destColor.red
            local gDest = destColor.green
            local bDest = destColor.blue

            local ro01 = rOrig / 255.0
            local go01 = gOrig / 255.0
            local bo01 = bOrig / 255.0

            local rd01 = rDest / 255.0
            local gd01 = gDest / 255.0
            local bd01 = bDest / 255.0

            local rc01 = u * ro01 + t * rd01
            local gc01 = u * go01 + t * gd01
            local bc01 = u * bo01 + t * bd01

            local rc255 = math.floor(rc01 * 255 + 0.5)
            local gc255 = math.floor(gc01 * 255 + 0.5)
            local bc255 = math.floor(bc01 * 255 + 0.5)

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

---@param origin number
---@param dest number
---@param t number
---@param range number
---@return number
local function lerpAngleCw(origin, dest, t, range)
    local valRange = range or 360.0
    local o = origin % valRange
    local d = dest % valRange
    local diff = d - o
    if diff == 0.0 then return d end

    local u = 1.0 - t
    if o < d then
        return (u * (o + valRange) + t * d) % valRange
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
    local valRange = range or 360.0
    local o = origin % valRange
    local d = dest % valRange
    local diff = d - o
    if diff == 0.0 then return o end

    local u = 1.0 - t
    if o > d then
        return (u * o + t * (d + valRange)) % valRange
    else
        return u * o + t * d
    end
end

local dlg = Dialog { title = "Gradient Import Export" }

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
        local apiVersion = app.apiVersion
        local sprite = nil
        if apiVersion >= 23 then
            sprite = app.sprite
        else
            ---@diagnostic disable-next-line: deprecated
            sprite = app.activeSprite
        end

        if not sprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local palIdx = 1
        local spritePalettes = sprite.palettes
        local palette = spritePalettes[palIdx]

        ---@type Color[]
        local selectedColors = {}

        ---@type integer[]
        local colorIndices = {}
        local range = app.range
        if range.sprite == sprite then
            colorIndices = range.colors
        end
        local lenColorIndices = #colorIndices

        if lenColorIndices > 0 then
            local i = 0
            while i < lenColorIndices do
                i = i + 1
                local colorIndex = colorIndices[i]
                local aseColor = palette:getColor(colorIndex)
                selectedColors[i] = aseColor
            end
        else
            local lenPalette = #palette
            local j = 0
            while j < lenPalette do
                local aseColor = palette:getColor(j)
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
        local apiVersion = app.apiVersion
        local sprite = nil
        if apiVersion >= 23 then
            sprite = app.sprite
        else
            ---@diagnostic disable-next-line: deprecated
            sprite = app.activeSprite
        end

        if not sprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local spriteSpec = sprite.spec
        local colorMode = spriteSpec.colorMode
        if colorMode == ColorMode.GRAY then
            app.alert {
                title = "Error",
                text = "Grayscale color mode not supported."
            }
            return
        end

        local args = dlg.data
        local shades = args.shades --[=[@as Color[]]=]
        local lenShades = #shades

        if lenShades > 0 then
            local palIdx = 1
            local spritePalettes = sprite.palettes
            local palette = spritePalettes[palIdx]

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
                local lenColorIndices = #colorIndices

                if lenColorIndices > 0 then
                    local iToFac = 0.0
                    if lenColorIndices > 1 then
                        iToFac = 1.0 / (lenColorIndices - 1.0)
                    end
                    local i = 0
                    while i < lenColorIndices do
                        local fac = i * iToFac
                        i = i + 1
                        local colorIndex = colorIndices[i]
                        local rTrg, gTrg, bTrg, aTrg = mixShades(shades, fac)
                        local aseColor = Color { r = rTrg, g = gTrg, b = bTrg, a = aTrg }
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
        local args = dlg.data
        local shades = args.shades --[=[@as Color[]]=]
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
        local apiVersion = app.apiVersion
        local sprite = nil
        local layer = nil
        local frame = nil
        if apiVersion >= 23 then
            sprite = app.sprite
            layer = app.layer
            frame = app.frame
        else
            ---@diagnostic disable-next-line: deprecated
            sprite = app.activeSprite
            ---@diagnostic disable-next-line: deprecated
            layer = app.activeLayer
            ---@diagnostic disable-next-line: deprecated
            frame = app.activeFrame
        end

        if not sprite then
            app.alert {
                title = "Error",
                text = "There is no active sprite."
            }
            return
        end

        local spriteSpec = sprite.spec
        local colorMode = spriteSpec.colorMode
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

        local cel = layer:cel(frame)
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

        local version = app.version
        if (version.major >= 1 and version.minor >= 3)
            or version.prereleaseLabel == "dev" then
            if layer.isTilemap then
                app.alert {
                    title = "Error",
                    text = "Tilemap layers not supported."
                }
                return
            end
        end

        local args = dlg.data
        local shades = args.shades --[=[@as Color[]]=]
        local lenShades = #shades

        if lenShades < 2 then
            app.alert {
                title = "Error",
                text = "At least two colors required."
            }
            return
        end

        app.transaction(function()
            if colorMode ~= ColorMode.RGB then
                app.command.ChangePixelFormat { format = "rgb" }
            end

            local srcImg = cel.image

            ---@type table<integer, boolean>
            local uniquesDict = {}

            local srcItr = srcImg:pixels()
            for srcPixel in srcItr do
                local srcHex = srcPixel()
                uniquesDict[srcHex] = true
            end

            local gamma = 2.2
            local invGamma = 1.0 / 2.2

            -- Cache methods used in loop.
            local tDecompose = app.pixelColor.rgbaA
            local bDecompose = app.pixelColor.rgbaB
            local gDecompose = app.pixelColor.rgbaG
            local rDecompose = app.pixelColor.rgbaR
            local rgbaCompose = app.pixelColor.rgba

            ---@type table<integer, integer>
            local srcToTrgDict = {}
            for srcHex, _ in pairs(uniquesDict) do
                local trgHex = 0
                local srcAlpha = tDecompose(srcHex)
                if srcAlpha > 0 then
                    local srcRed = rDecompose(srcHex)
                    local srcGreen = gDecompose(srcHex)
                    local srcBlue = bDecompose(srcHex)

                    local r01 = srcRed / 255.0
                    local g01 = srcGreen / 255.0
                    local b01 = srcBlue / 255.0

                    local rLin = r01 ^ gamma
                    local gLin = g01 ^ gamma
                    local bLin = b01 ^ gamma

                    local y = 0.2126 * rLin
                        + 0.7152 * gLin
                        + 0.0722 * bLin
                    local t = y ^ invGamma

                    local rTrg, gTrg, bTrg, aTrg = mixShades(shades, t)
                    trgHex = rgbaCompose(rTrg, gTrg, bTrg, aTrg)
                end

                srcToTrgDict[srcHex] = trgHex
            end

            local trgImg = srcImg:clone()
            local trgItr = trgImg:pixels()
            for pixel in trgItr do
                pixel(srcToTrgDict[pixel()])
            end

            -- if not trgImg:isEmpty() then
            local mapLayer = sprite:newLayer()
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
    focus = true,
    filetypes = { "ggr" },
    open = true
}

dlg:newrow { always = false }

dlg:button {
    id = "import",
    text = "&IMPORT",
    focus = false,
    onclick = function()
        local args = dlg.data
        local filepath = args.importFilepath --[[@as string]]
        local samples = args.samples or defaults.samples --[[@as integer]]

        if (not filepath) or (#filepath < 1) then
            app.alert {
                title = "Error",
                text = "Filepath is empty."
            }
            return
        end

        local fileExt = string.lower(
            app.fs.fileExtension(filepath))
        if fileExt ~= "ggr" then
            app.alert {
                title = "Error",
                text = "File format is not ggr."
            }
            return
        end

        local file, err = io.open(filepath, "r")

        if file ~= nil then
            local strlower = string.lower
            local strgmatch = string.gmatch
            local strsub = string.sub

            ---@type number[][]
            local keys = {}

            local linesItr = file:lines()
            for line in linesItr do
                local lc = strlower(line)
                if lc == "gimp gradient" then
                    -- Skip header.
                elseif strsub(lc, 1, 1) == '#' then
                    -- Skip comments.
                elseif strsub(lc, 1, 4) == "name" then
                    -- Skip names.
                elseif #lc > 0 then
                    ---@type string[]
                    local tokens = {}
                    local lenTokens = 0
                    for token in strgmatch(line, "%S+") do
                        lenTokens = lenTokens + 1
                        tokens[lenTokens] = token
                    end

                    if lenTokens > 12 then
                        ---@type number[]
                        local seg = {}
                        local j = 0
                        while j < 13 do
                            j = j + 1
                            local parsed = tonumber(tokens[j])
                            local value = 0
                            if parsed then value = parsed end
                            seg[j] = value
                        end
                        keys[#keys + 1] = seg
                    end
                end
            end

            -- Constants used in loop.
            local pi = math.pi
            local halfPi = pi * 0.5
            local logHalf = -0.6931471805599453

            -- Methods used in loop.
            local floor = math.floor
            local log = math.log
            local sin = math.sin
            local sqrt = math.sqrt
            local exp = math.exp

            ---@type Color[]
            local parsedColors = {}
            local lenKeys = #keys
            local iToFac = 1.0 / (samples - 1.0)
            local i = 0
            while i < samples do
                local iFac = i * iToFac
                i = i + 1

                local r01 = 0.0
                local g01 = 0.0
                local b01 = 0.0
                local a01 = 0.0

                if iFac <= keys[1][1] then
                    -- If less than lower bound, set to left color of first key.
                    local seg = keys[1]
                    r01 = seg[4]
                    g01 = seg[5]
                    b01 = seg[6]
                    a01 = seg[7]
                elseif iFac >= keys[lenKeys][3] then
                    -- If greater than upper bound, set to right color of last key.
                    local seg = keys[lenKeys]
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
                        segFound = seg[1] <= iFac
                            and iFac <= seg[3]
                    until segFound or m >= lenKeys

                    -- Unpack weights for left, right and middle.
                    local segLft = seg[1]
                    local segMid = seg[2]
                    local segRgt = seg[3]

                    -- Find normalized step.
                    local denom = 0.0
                    if segLft ~= segRgt then
                        denom = 1.0 / (segRgt - segLft)
                    end
                    local mid = (segMid - segLft) * denom
                    local pos = (iFac - segLft) * denom

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

                    local blendFuncCode = floor(seg[12])
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

                    local r01Lft = seg[4]
                    local g01Lft = seg[5]
                    local b01Lft = seg[6]
                    local a01Lft = seg[7]

                    local r01Rgt = seg[8]
                    local g01Rgt = seg[9]
                    local b01Rgt = seg[10]
                    local a01Rgt = seg[11]

                    local colorSpaceCode = floor(seg[13])
                    local isHsbCcw = colorSpaceCode == 1
                    local isHsbCw = colorSpaceCode == 2
                    local isHsb = isHsbCcw or isHsbCw
                    local lftIsGray = r01Lft == g01Lft
                        and g01Lft == b01Lft
                    local rgtIsGray = r01Rgt == g01Rgt
                        and g01Rgt == b01Rgt
                    local isValidHsb = not (lftIsGray or rgtIsGray)

                    if isHsb and isValidHsb then
                        -- HSB
                        local aseColorLft = Color {
                            r = floor(r01Lft * 255.0 + 0.5),
                            g = floor(g01Lft * 255.0 + 0.5),
                            b = floor(b01Lft * 255.0 + 0.5)
                        }

                        local hLft = aseColorLft.hsvHue
                        local sLft = aseColorLft.hsvSaturation
                        local vLft = aseColorLft.hsvValue

                        local aseColorRgt = Color {
                            r = floor(r01Rgt * 255.0 + 0.5),
                            g = floor(g01Rgt * 255.0 + 0.5),
                            b = floor(b01Rgt * 255.0 + 0.5)
                        }

                        local hRgt = aseColorRgt.hsvHue
                        local sRgt = aseColorRgt.hsvSaturation
                        local vRgt = aseColorRgt.hsvValue

                        local u = 1.0 - localFac
                        local sTrg = u * sLft + localFac * sRgt
                        local vTrg = u * vLft + localFac * vRgt

                        local equalHues = math.abs(hRgt - hLft) < 1.0 / 720.0
                        local hTrg = 0.0
                        if isHsbCcw then
                            if equalHues then
                                hLft = hLft + 1.0 / 1080.0
                            end
                            hTrg = lerpAngleCcw(hLft, hRgt, localFac, 360.0)
                        elseif isHsbCw then
                            if equalHues then
                                hLft = hLft - 1.0 / 1080.0
                            end
                            hTrg = lerpAngleCw(hLft, hRgt, localFac, 360.0)
                        end

                        local hsbMix = Color {
                            hue = hTrg,
                            saturation = sTrg,
                            value = vTrg
                        }

                        r01 = hsbMix.red / 255.0
                        g01 = hsbMix.green / 255.0
                        b01 = hsbMix.blue / 255.0
                        a01 = u * a01Lft + localFac * a01Rgt
                    else
                        -- Standard RGB.
                        local u = 1.0 - localFac
                        r01 = u * r01Lft + localFac * r01Rgt
                        g01 = u * g01Lft + localFac * g01Rgt
                        b01 = u * b01Lft + localFac * b01Rgt
                        a01 = u * a01Lft + localFac * a01Rgt
                    end
                end

                local aseColorTrg = Color {
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
    focus = false,
    filetypes = { "ggr" },
    save = true
}

dlg:newrow { always = false }

dlg:button {
    id = "export",
    text = "&EXPORT",
    focus = false,
    onclick = function()
        local args = dlg.data
        local filepath = args.exportFilepath --[[@as string]]
        if (not filepath) or (#filepath < 1) then
            app.alert {
                title = "Error",
                text = "Filepath is empty."
            }
            return
        end

        local fileExt = app.fs.fileExtension(filepath)
        if string.lower(fileExt) ~= "ggr" then
            app.alert {
                title = "Error",
                text = "Extension is not ggr."
            }
            return
        end

        local shades = args.shades --[=[@as Color[]]=]
        local lenShades = #shades
        if lenShades < 2 then
            app.alert {
                title = "Error",
                text = "At least two colors required."
            }
            return
        end

        local blendFuncStr = args.blendFunc
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

        local colorSpaceStr = args.colorSpace
            or defaults.colorSpace --[[@as string]]
        local colorSpaceCode = 0
        if colorSpaceStr == "HSB_CCW" then
            colorSpaceCode = 1
        elseif colorSpaceStr == "HSB_CW" then
            colorSpaceCode = 2
        end

        -- Each color key has a left edge (1), middle point (2)
        -- and right edge (3). Colors are placed on the left
        -- edge as red, green blue and alpha (4, 5, 6, 7) and
        -- on the right edge (8, 9, 10, 11). The easing function
        -- is encoded in column 12. The color space is in 13.
        local headerStrs = {
            "GIMP Gradient\n",
            string.format("Name: %s\n", app.fs.fileTitle(filepath)),
            string.format("%d\n", lenShades - 1)
        }

        local currClr = shades[1]
        local prevStep = 0.0
        local prevClrStr = aseColorToGgrString(currClr)

        ---@type string[]
        local segStrs = {}

        local i = 1
        while i < lenShades do
            local currStep = i / (lenShades - 1.0)
            i = i + 1
            currClr = shades[i]
            local currClrStr = aseColorToGgrString(currClr)

            segStrs[i - 1] = string.format(
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

        local ggrStr = string.format(
            "%s%s",
            table.concat(headerStrs),
            table.concat(segStrs, "\n"))

        local file, err = io.open(filepath, "w")
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

dlg:show { wait = false }
