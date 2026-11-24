-- Race-boat dashboard for the Radiomaster MT12 (EdgeTX 2.12, 128x64).
-- Version 1.01
-- Install: copy to SCRIPTS/TELEMETRY/boat.lua on the SD card, then
-- Model > Display > Script > boat. From the Home Screen, press the
-- Telemetry button to open these pages.
-- The script only displays values. Arming safety and the throttle limit
-- must be set up in the model itself (special functions, curves).

---------------------------------------------------------------------------
-- SETTINGS
-- Source names are the Lua names EdgeTX uses ("sa", "s1", "RxBt", ...).
-- Where a list { ... } is given, the first name that exists on the radio is
-- used; a single name in quotes also works.
---------------------------------------------------------------------------

-- Channels ----------------------------------------------------------------
-- Channels are counted from 0: 0 = CH1, 1 = CH2, 2 = CH3, ...
-- The screen shows what the channel really sends (after mixes and overrides).
local THR_OUT = 1               -- throttle channel (CH2)
local RUD_OUT = 2               -- steering channel (CH3)
local THR_SIGN = 1              -- 1 or -1: flip if forward shows as reverse
local RUD_SIGN = 1              -- 1 or -1: flip if steering shows mirrored

-- Throttle bar (left of the boat) ------------------------------------------
-- Throttle % at the bottom and the top of the bar. -100/100 puts 0% in the
-- middle; use 0/100 for a forward-only ESC.
local THR_BAR_MIN = -100
local THR_BAR_MAX = 100
local WAKE_MIN = 0              -- throttle % above which the wake appears

-- Steering bar (bottom) and rudder ----------------------------------------
local RUD_BAR_MAX = 100         -- steering % that reaches the end of the bar
local RUDDER_SWING = 1.25       -- how far the rudder on the boat swings, 0 = fixed

-- Trims -------------------------------------------------------------------
-- Throttle trim = arrow beside the left bar, steering trim = arrow under
-- the steering bar. Both become a small square when the trim is centered.
local THR_TRIM_SRC = { "trim-th", "trim-TH", "trim-thr", "trim-T2", "trim-t2" }
local RUD_TRIM_SRC = { "trim-st", "trim-ST", "trim-ste", "trim-T1", "trim-t1" }
local THR_TRIM_SIGN = 1         -- 1 or -1: flip the throttle trim arrow
local RUD_TRIM_SIGN = 1         -- 1 or -1: flip the steering trim arrow

-- Arming and banner -------------------------------------------------------
-- Armed is read from a logical switch when ARM_LS is set, otherwise from a
-- physical switch position. Use whatever the model uses to unlock the outputs.
local ARM_LS = 2                -- logical switch number (2 = L02), 0 = use ARM_SRC
local ARM_SRC = { "sa", "SA" }  -- switch used when ARM_LS = 0
local ARMED_POS = "down"        -- position of ARM_SRC that means armed: "up", "mid" or "down"
local ARMED_TEXT = "ARMED"      -- banner text when armed (A-Z, 0-9, - _ space)
local SAFE_TEXT = "SAFE"        -- banner text when not armed
local SHOW_NAME = true          -- when safe, alternate SAFE_TEXT with the model name
local BANNER_TIME = 1.5         -- seconds each for SAFE_TEXT and the model name

-- Throttle limit (right bar) ----------------------------------------------
-- Should mirror the curve in the model that limits throttle with a pot.
-- Pot fully down, centered and fully up give these limit % (linear between).
local LIMIT_SRC = { "s1", "S1", "p1", "P1" }
local LIMIT_LOW = 10
local LIMIT_MID = 50
local LIMIT_HIGH = 100
local LIMIT_BAR_MIN = 0         -- limit % shown as an empty bar
local LIMIT_BAR_MAX = 100       -- limit % shown as a full bar

-- Transmitter battery (top left) ------------------------------------------
local TX_SRC = "tx-voltage"
local TX_MIN = 6.4              -- volts at 0% (linear between min and max)
local TX_MAX = 8.4              -- volts at 100%
local TX_WARN = 20              -- blinks below this %

-- Boat battery (bottom left) ----------------------------------------------
local RX_SRC = { "RxBt", "RXbt", "RXBt" }
local RX_CELLS = 2              -- cells in series
local CELL_MIN = 3.40           -- volts per cell at 0%
local CELL_MAX = 4.20           -- volts per cell at 100%
local RX_CURVE = true           -- true: LiPo discharge curve, false: linear
local RX_PER_CELL = true        -- treat readings of 2.5-4.45 V as one cell (x RX_CELLS)
local RX_WARN = 10              -- blinks below this %

-- Link (right column, ExpressLRS sensor names) ----------------------------
local LQ_SRC = { "RQly", "LQly", "Rqly" }
local LQ_MIN_SRC = { "RQly-", "LQly-", "Rqly-" }
local TPWR_SRC = { "TPWR", "TPwr" }
local RSSI_SRC = { "1RSS", "RSSi", "RSSI" }
local LQ_WARN = 50              -- big LQ number blinks below this %
local LQ_MIN_WARN = 50          -- Min. LQ blinks below this %
-- Without telemetry the banner alternates NO_LINK_TEXT with the time since
-- the link was lost; the last received values stay on screen, blinking.
local NO_LINK_TEXT = "NO LINK"

-- Blinking ----------------------------------------------------------------
local BLINK_TIME = 1.0          -- seconds per blink cycle
local BLINK_ON = 0.6            -- part of the cycle a warning is visible (0-1)

---------------------------------------------------------------------------
-- END OF SETTINGS
---------------------------------------------------------------------------

-- LiPo discharge curve per cell, rescaled to CELL_MIN..CELL_MAX at load.
local LIPO_CELL = {
  {4.200, 100}, {4.150, 95}, {4.110, 90}, {4.080, 85}, {4.020, 80},
  {3.980, 75}, {3.950, 70}, {3.910, 65}, {3.870, 60}, {3.850, 55},
  {3.840, 50}, {3.820, 45}, {3.800, 40}, {3.790, 35}, {3.770, 30},
  {3.750, 25}, {3.730, 20}, {3.710, 15}, {3.690, 10}, {3.610, 5},
  {3.270, 0},
}
local LIPO = {}
for i = 1, #LIPO_CELL do
  local f = (LIPO_CELL[i][1] - 3.27) / (4.20 - 3.27)
  LIPO[i] = { (CELL_MIN + f * (CELL_MAX - CELL_MIN)) * RX_CELLS, LIPO_CELL[i][2] }
end

local BLACK = FORCE
local WHITE = ERASE

-- 7-row font: battery readouts and the throttle readout.
local F7 = {
  ["0"] = { ".##.", "#..#", "#..#", "#.##", "##.#", "#..#", ".##." },
  ["1"] = { ".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###" },
  ["2"] = { ".##.", "#..#", "...#", "..#.", ".#..", "#...", "####" },
  ["3"] = { "###.", "...#", "...#", ".##.", "...#", "...#", "###." },
  ["4"] = { "..#.", ".##.", "#.#.", "#.#.", "####", "..#.", "..#." },
  ["5"] = { "####", "#...", "###.", "...#", "...#", "#..#", ".##." },
  ["6"] = { ".##.", "#...", "#...", "###.", "#..#", "#..#", ".##." },
  ["7"] = { "####", "...#", "...#", "..#.", "..#.", ".#..", ".#.." },
  ["8"] = { ".##.", "#..#", "#..#", ".##.", "#..#", "#..#", ".##." },
  ["9"] = { ".##.", "#..#", "#..#", ".###", "...#", "...#", ".##." },
  ["."] = { ".", ".", ".", ".", ".", ".", "#" },
  ["%"] = { "##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##" },
  ["V"] = { "#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.." },
  ["-"] = { "...", "...", "...", "###", "...", "...", "..." },
  ["+"] = { "...", ".#.", ".#.", "###", ".#.", ".#.", "..." },
  ["m"] = { ".....", ".....", "####.", "#.#.#", "#.#.#", "#.#.#", "#.#.#" },
  ["W"] = { "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#" },
}

-- 6-row font: the link column.
local F6 = {
  ["0"] = { ".##.", "#..#", "#.##", "##.#", "#..#", ".##." },
  ["1"] = { ".#.", "##.", ".#.", ".#.", ".#.", "###" },
  ["2"] = { ".##.", "#..#", "..#.", ".#..", "#...", "####" },
  ["3"] = { "###.", "...#", ".##.", "...#", "...#", "###." },
  ["4"] = { "..#.", ".##.", "#.#.", "####", "..#.", "..#." },
  ["5"] = { "####", "#...", "###.", "...#", "#..#", ".##." },
  ["6"] = { ".##.", "#...", "###.", "#..#", "#..#", ".##." },
  ["7"] = { "####", "...#", "..#.", "..#.", ".#..", ".#.." },
  ["8"] = { ".##.", "#..#", ".##.", "#..#", "#..#", ".##." },
  ["9"] = { ".##.", "#..#", "#..#", ".###", "...#", ".##." },
  ["-"] = { "...", "...", "###", "...", "...", "..." },
  ["."] = { ".", ".", ".", ".", ".", "#" },
  [":"] = { ".", "#", ".", ".", "#", "." },
  [" "] = { "", "", "", "", "", "" },
  ["M"] = { "#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#" },
  ["i"] = { "#", ".", "#", "#", "#", "#" },
  ["n"] = { "...", "##.", "#.#", "#.#", "#.#", "#.#" },
  ["L"] = { "#..", "#..", "#..", "#..", "#..", "###" },
  ["Q"] = { ".##.", "#..#", "#..#", "#..#", "#.#.", ".#.#" },
  ["R"] = { "##.", "#.#", "#.#", "##.", "#.#", "#.#" },
  ["S"] = { ".##", "#..", ".#.", "..#", "..#", "##." },
  ["I"] = { "#", "#", "#", "#", "#", "#" },
  ["m"] = { ".....", "####.", "#.#.#", "#.#.#", "#.#.#", "#.#.#" },
  ["W"] = { "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#." },
}

-- 5-row font: model name.
local F5 = {
  ["A"] = { ".#.", "#.#", "###", "#.#", "#.#" },
  ["B"] = { "##.", "#.#", "##.", "#.#", "##." },
  ["C"] = { ".##", "#..", "#..", "#..", ".##" },
  ["D"] = { "##.", "#.#", "#.#", "#.#", "##." },
  ["E"] = { "###", "#..", "##.", "#..", "###" },
  ["F"] = { "###", "#..", "##.", "#..", "#.." },
  ["G"] = { ".##", "#..", "#.#", "#.#", ".##" },
  ["H"] = { "#.#", "#.#", "###", "#.#", "#.#" },
  ["I"] = { "###", ".#.", ".#.", ".#.", "###" },
  ["J"] = { "..#", "..#", "..#", "#.#", ".#." },
  ["K"] = { "#.#", "#.#", "##.", "#.#", "#.#" },
  ["L"] = { "#..", "#..", "#..", "#..", "###" },
  ["M"] = { "#.#", "###", "###", "#.#", "#.#" },
  ["N"] = { "##.", "#.#", "#.#", "#.#", "#.#" },
  ["O"] = { ".#.", "#.#", "#.#", "#.#", ".#." },
  ["P"] = { "##.", "#.#", "##.", "#..", "#.." },
  ["Q"] = { ".#.", "#.#", "#.#", "##.", ".##" },
  ["R"] = { "##.", "#.#", "##.", "#.#", "#.#" },
  ["S"] = { ".##", "#..", ".#.", "..#", "##." },
  ["T"] = { "###", ".#.", ".#.", ".#.", ".#." },
  ["U"] = { "#.#", "#.#", "#.#", "#.#", "###" },
  ["V"] = { "#.#", "#.#", "#.#", "#.#", ".#." },
  ["W"] = { "#.#", "#.#", "###", "###", "#.#" },
  ["X"] = { "#.#", "#.#", ".#.", "#.#", "#.#" },
  ["Y"] = { "#.#", "#.#", ".#.", ".#.", ".#." },
  ["Z"] = { "###", "..#", ".#.", "#..", "###" },
  ["0"] = { "###", "#.#", "#.#", "#.#", "###" },
  ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
  ["2"] = { "##.", "..#", ".#.", "#..", "###" },
  ["3"] = { "##.", "..#", ".#.", "..#", "##." },
  ["4"] = { "#.#", "#.#", "###", "..#", "..#" },
  ["5"] = { "###", "#..", "##.", "..#", "##." },
  ["6"] = { ".##", "#..", "###", "#.#", "###" },
  ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
  ["8"] = { "###", "#.#", "###", "#.#", "###" },
  ["9"] = { "###", "#.#", "###", "..#", "##." },
  ["-"] = { "...", "...", "###", "...", "..." },
  ["_"] = { "...", "...", "...", "...", "###" },
  [" "] = { ".", ".", ".", ".", "." },
}

-- Banner lettering, drawn white on the black bar.
local HD = {
  ["A"] = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
  ["B"] = { "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####." },
  ["C"] = { ".####", "#....", "#....", "#....", "#....", "#....", ".####" },
  ["D"] = { "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####." },
  ["E"] = { "####", "#...", "#...", "###.", "#...", "#...", "####" },
  ["F"] = { "####", "#...", "#...", "###.", "#...", "#...", "#..." },
  ["G"] = { ".####", "#....", "#....", "#.###", "#...#", "#...#", ".####" },
  ["H"] = { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
  ["I"] = { "###", ".#.", ".#.", ".#.", ".#.", ".#.", "###" },
  ["J"] = { "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.." },
  ["K"] = { "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#" },
  ["L"] = { "#...", "#...", "#...", "#...", "#...", "#...", "####" },
  ["M"] = { "#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#" },
  ["N"] = { "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#" },
  ["O"] = { ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
  ["P"] = { "####.", "#...#", "#...#", "####.", "#....", "#....", "#...." },
  ["Q"] = { ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#" },
  ["R"] = { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
  ["S"] = { ".####", "#....", "#....", ".###.", "....#", "....#", "####." },
  ["T"] = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." },
  ["U"] = { "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###." },
  ["V"] = { "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.." },
  ["W"] = { "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#" },
  ["X"] = { "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#" },
  ["Y"] = { "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.." },
  ["Z"] = { "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####" },
  ["0"] = { ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###." },
  ["1"] = { ".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###" },
  ["2"] = { ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####" },
  ["3"] = { "####.", "....#", "....#", ".###.", "....#", "....#", "####." },
  ["4"] = { "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#." },
  ["5"] = { "#####", "#....", "####.", "....#", "....#", "#...#", ".###." },
  ["6"] = { ".###.", "#....", "#....", "####.", "#...#", "#...#", ".###." },
  ["7"] = { "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..." },
  ["8"] = { ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###." },
  ["9"] = { ".###.", "#...#", "#...#", ".####", "....#", "....#", ".###." },
  ["-"] = { "...", "...", "...", "###", "...", "...", "..." },
  ["_"] = { "....", "....", "....", "....", "....", "....", "####" },
  [":"] = { ".", ".", "#", ".", ".", "#", "." },
  [" "] = { "..", "..", "..", "..", "..", "..", ".." },
}

local STAR = { "..#..", "#####", ".###.", ".#.#.", "#...#" }

local BIG = {
  ["0"] = { "..#####..", ".#######.", "###...###", "##.....##", "##.....##", "##.....##", "##.....##",
            "##.....##", "##.....##", "##.....##", "##.....##", "###...###", ".#######.", "..#####.." },
  ["1"] = { "....##...", "...###...", "..####...", ".##.##...", "....##...", "....##...", "....##...",
            "....##...", "....##...", "....##...", "....##...", "....##...", "..######.", "..######." },
  ["2"] = { "..#####..", ".#######.", "###...###", "##.....##", ".......##", "......###", ".....###.",
            "....###..", "...###...", "..###....", ".###.....", "###......", "#########", "#########" },
  ["3"] = { "..#####..", ".#######.", "###...###", ".......##", "......###", "...#####.", "...#####.",
            "......###", ".......##", ".......##", ".......##", "###...###", ".#######.", "..#####.." },
  ["4"] = { ".....##..", "....###..", "...####..", "..##.##..", ".##..##..", "##...##..", "##...##..",
            "#########", "#########", ".....##..", ".....##..", ".....##..", ".....##..", ".....##.." },
  ["5"] = { "#########", "#########", "##.......", "##.......", "##.####..", "########.", "###...###",
            ".......##", ".......##", ".......##", ".......##", "###...###", ".#######.", "..#####.." },
  ["6"] = { "..#####..", ".#######.", "###...###", "##.......", "##.......", "##.####..", "########.",
            "###...###", "##.....##", "##.....##", "##.....##", "###...###", ".#######.", "..#####.." },
  ["7"] = { "#########", "#########", ".......##", "......###", ".....###.", "....###..", "....##...",
            "...###...", "...##....", "...##....", "..###....", "..##.....", "..##.....", "..##....." },
  ["8"] = { "..#####..", ".#######.", "###...###", "##.....##", "###...###", ".#######.", ".#######.",
            "###...###", "##.....##", "##.....##", "##.....##", "###...###", ".#######.", "..#####.." },
  ["9"] = { "..#####..", ".#######.", "###...###", "##.....##", "##.....##", "##.....##", "###...###",
            ".########", "..####.##", ".......##", ".......##", "###...###", ".#######.", "..#####.." },
  ["-"] = { ".........", ".........", ".........", ".........", ".........", ".........", "#########",
            "#########", ".........", ".........", ".........", ".........", ".........", "........." },
}

local RADIO = {
  "..#..###.",
  "..#.#...#",
  "#####.#.#",
  "#####...#",
  ".##..###.",
  ".##......",
  ".##......",
  "####.....",
}

local SIDE = {
  "........###......",
  "....##..######...",
  "..###############",
  "##............##.",
  "##############...",
}

local HULL = {
  "....##....",
  "...#..#...",
  "...#..#...",
  "..#....#..",
  "..#.##.#..",
  ".#.#..#.#.",
  ".#.#..#.#.",
  ".#.#..#.#.",
  "#..#..#..#",
  "#..#..#..#",
  "#..#..#..#",
  "#.#....#.#",
  "#.#.##.#.#",
  "#.######.#",
  "#.##..##.#",
  "#.#....#.#",
  "#.#....#.#",
  "#.#....#.#",
  "#.#.##.#.#",
  "#.######.#",
  "#.##..##.#",
  "#.##..##.#",
  "#.##..##.#",
  "#.##..##.#",
  "#.#.##.#.#",
  "#.#....#.#",
  "##########",
  "...####...",
  "....##....",
}

local LQ_LABEL = {
  "#.....###.",
  "#....#...#",
  "#....#...#",
  "#....#...#",
  "#....#.#.#",
  "#....#..#.",
  "####..##.#",
}

local PWR_ICON = { "#...#", "#.##.", "#...#", "..##.", "..##.", ".###.", ".####" }
local RSSI_ICON = { "#...#", "#.#.#", ".###.", "..#..", "..#..", "..#..", ".###." }

local PILL = {
  { 1, 1, 20 },
  { 2, 1, 1 }, { 2, 3, 17 }, { 2, 21, 21 },
  { 3, 1, 1 }, { 3, 3, 18 }, { 3, 22, 22 },
  { 4, 1, 1 }, { 4, 3, 19 }, { 4, 23, 23 },
  { 5, 1, 1 }, { 5, 3, 18 }, { 5, 22, 22 },
  { 6, 1, 1 }, { 6, 3, 17 }, { 6, 21, 21 },
  { 7, 1, 20 },
}

local CHEVRON = { 0, 0, 0, 1, 1, 2, 2, 3, 1, 2, 0, 1, 0, 0 }
local CHEVRON_X = { 26, 30, 35 }

local WAKE = {
  { 59, 32, 59, 33, 59, 34, 58, 35, 58, 36, 57, 37, 57, 38, 57, 39, 56, 40, 56, 41,
    55, 42, 55, 43, 54, 44, 54, 45, 53, 46, 53, 47 },
  { 58, 41, 58, 42, 58, 43, 57, 44, 57, 45, 57, 46 },
  { 61, 43, 61, 44, 61, 45, 60, 46, 60, 47 },
}

local CELL_X = { 1, 7, 13, 18, 24, 30 }
local CELL_W = { 5, 5, 4, 5, 5, 4 }
local BLOCK_X = { 102, 106, 110, 114, 118, 122, 126 }
local BLOCK_W = { 3, 3, 3, 3, 3, 3, 2 }

local txName, rxName, lqName, lqMinName, pwrName, rssiName
local potName, armName, thrTrimName, rudTrimName
local armedText, armedFont, safeText, safeFont, noLinkText, noLinkFont
local link = { had = false, lostAt = nil, rxRaw = 0, lq = 0, lqMin = 0, tpwr = 0, rssi = 0 }
local ARMED_INDEX = ({ up = 0, mid = 1, down = 2 })[ARMED_POS] or 2

local compiled = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return math.ceil(v - 0.5)
end

local function pick(list)
  if type(list) ~= "table" then return list end
  for i = 1, #list do
    if getFieldInfo(list[i]) then return list[i] end
  end
  return list[1]
end

local function txPct(v)
  return round(clamp((v - TX_MIN) / (TX_MAX - TX_MIN) * 100, 0, 100))
end

local function lipoPct(v)
  if not RX_CURVE then
    local lo, hi = CELL_MIN * RX_CELLS, CELL_MAX * RX_CELLS
    return round(clamp((v - lo) / (hi - lo) * 100, 0, 100))
  end
  if v >= LIPO[1][1] then return 100 end
  if v <= LIPO[#LIPO][1] then return 0 end
  for i = 1, #LIPO - 1 do
    local v1, p1 = LIPO[i][1], LIPO[i][2]
    local v2, p2 = LIPO[i + 1][1], LIPO[i + 1][2]
    if v <= v1 and v >= v2 then
      return round(p1 + (p2 - p1) * (v1 - v) / (v1 - v2))
    end
  end
  return 0
end

local function asPack(v)
  if RX_PER_CELL and v >= 2.5 and v <= 4.45 then return v * RX_CELLS end
  return v
end

local function outputUnit(idx, sign)
  local v = getOutputValue(idx) or 0
  return clamp(v, -1024, 1024) * sign / 1024
end

local function isArmed()
  if ARM_LS > 0 then
    return getLogicalSwitchValue ~= nil and getLogicalSwitchValue(ARM_LS - 1) == true
  end
  local v = getValue(armName) or 0
  local pos = 1
  if v < -256 then pos = 0 elseif v > 256 then pos = 2 end
  return pos == ARMED_INDEX
end

local function limitPct()
  local raw = getValue(potName) or 0
  local p = clamp(raw * 100 / 1024, -100, 100)
  if p <= 0 then return round(LIMIT_LOW + (LIMIT_MID - LIMIT_LOW) * (p + 100) / 100) end
  return round(LIMIT_MID + (LIMIT_HIGH - LIMIT_MID) * p / 100)
end

local function hl(x1, x2, y, f)
  lcd.drawLine(x1, y, x2, y, SOLID, f)
end

local function vl(x, y1, y2, f)
  lcd.drawLine(x, y1, x, y2, SOLID, f)
end

local function pt(x, y, f)
  lcd.drawLine(x, y, x, y, SOLID, f)
end

local function compile(rows)
  local c = compiled[rows]
  if c then return c end
  local runs = {}
  local w = 0
  for j = 1, #rows do
    local row = rows[j]
    if #row > w then w = #row end
    local i = 1
    while true do
      local s, e = string.find(row, "#+", i)
      if not s then break end
      runs[#runs + 1] = j - 1
      runs[#runs + 1] = s - 1
      runs[#runs + 1] = e - 1
      i = e + 1
    end
  end
  c = { w = w, runs = runs }
  compiled[rows] = c
  return c
end

local function sprite(x, y, rows, f)
  local runs = compile(rows).runs
  for k = 1, #runs, 3 do
    hl(x + runs[k + 1], x + runs[k + 2], y + runs[k], f)
  end
end

local function textw(font, s)
  local w = 0
  for i = 1, #s do
    local g = font[string.sub(s, i, i)]
    if g then w = w + compile(g).w + 1 end
  end
  if w > 0 then w = w - 1 end
  return w
end

local function text(font, x, y, s, f)
  for i = 1, #s do
    local g = font[string.sub(s, i, i)]
    if g then
      sprite(x, y, g, f)
      x = x + compile(g).w + 1
    end
  end
  return x
end

local function battery(y, pct, filled)
  hl(0, 34, y, BLACK)
  hl(0, 34, y + 6, BLACK)
  vl(0, y + 1, y + 5, BLACK)
  vl(34, y + 1, y + 5, BLACK)
  lcd.drawFilledRectangle(35, y + 2, 2, 3, BLACK)
  if not filled then return end
  local lit = math.floor(clamp(pct, 0, 100) * 6 / 100)
  if pct > 0 and lit < 1 then lit = 1 end
  for i = 1, lit do
    lcd.drawFilledRectangle(CELL_X[i], y + 1, CELL_W[i], 5, BLACK)
  end
end

local G_TOP, G_BOT = 11, 55
local G_MID = math.floor((G_TOP + G_BOT) / 2)
local G_H = G_BOT - G_TOP - 1
local BOAT_DY = -5

local function gaugeFrame(x, tickX, dir)
  hl(x, x + 4, G_TOP, BLACK)
  hl(x, x + 4, G_BOT, BLACK)
  vl(x, G_TOP + 1, G_BOT - 1, BLACK)
  vl(x + 4, G_TOP + 1, G_BOT - 1, BLACK)
  local span = math.floor((G_BOT - G_TOP) / 4)
  for y = G_TOP, G_BOT do
    local k = (y - G_TOP) % span
    if k == 0 then
      hl(math.min(tickX, tickX + dir), math.max(tickX, tickX + dir), y, BLACK)
    elseif k % 2 == 0 and k < span - 1 then
      pt(tickX, y, BLACK)
    end
  end
end

local function gaugeFill(x, frac)
  local n = round(clamp(frac, 0, 1) * G_H)
  if n > 0 then
    lcd.drawFilledRectangle(x, G_BOT - n, 3, n, BLACK)
  end
end

local function throttleGauge(thr, trim)
  gaugeFrame(43, 49, 1)
  gaugeFill(44, (thr * 100 - THR_BAR_MIN) / (THR_BAR_MAX - THR_BAR_MIN))
  if trim == 0 then
    lcd.drawFilledRectangle(52, G_MID - 1, 2, 3, BLACK)
  else
    local m = clamp(G_MID - round(trim * (G_H / 2 - 1)), G_TOP + 2, G_BOT - 2)
    pt(52, m, BLACK)
    vl(53, m - 1, m + 1, BLACK)
  end
end

local function capGauge(cap)
  gaugeFrame(82, 80, -1)
  gaugeFill(83, (cap - LIMIT_BAR_MIN) / (LIMIT_BAR_MAX - LIMIT_BAR_MIN))
end

local function drawBoat(thr, rud)
  sprite(60, 16 + BOAT_DY, HULL, BLACK)
  local r = clamp(rud, -1, 1)
  for i = 0, 4 do
    local off = round(r * i * RUDDER_SWING)
    hl(64 + off, 65 + off, 45 + BOAT_DY + i, BLACK)
  end
  if thr <= 0 or thr * 100 <= WAKE_MIN then return end
  for w = 1, #WAKE do
    local line = WAKE[w]
    local n = #line / 2
    local show = math.ceil(thr * n)
    for k = 1, show do
      local x, y = line[2 * k - 1], line[2 * k] + BOAT_DY
      pt(x, y, BLACK)
      pt(129 - x, y, BLACK)
    end
  end
end

local function rudderBar(rud, trim)
  hl(46, 83, 58, BLACK)
  hl(46, 83, 61, BLACK)
  vl(46, 59, 60, BLACK)
  vl(83, 59, 60, BLACK)
  pt(44, 58, BLACK)
  hl(43, 44, 59, BLACK)
  hl(43, 44, 60, BLACK)
  pt(44, 61, BLACK)
  pt(85, 58, BLACK)
  hl(85, 86, 59, BLACK)
  hl(85, 86, 60, BLACK)
  pt(85, 61, BLACK)
  local mx = 64 + round(clamp(rud * 100 / RUD_BAR_MAX, -1, 1) * 16)
  hl(mx, mx + 1, 59, BLACK)
  hl(mx, mx + 1, 60, BLACK)
  if trim == 0 then
    hl(64, 65, 62, BLACK)
    hl(64, 65, 63, BLACK)
  else
    local tx = 64 + round(trim * 16)
    pt(tx, 62, BLACK)
    hl(tx - 1, tx + 1, 63, BLACK)
  end
end

local function fitName(name)
  if textw(HD, name) <= 46 then return name, HD end
  while #name > 1 and textw(F5, name) > 46 do
    name = string.sub(name, 1, #name - 1)
  end
  return name, F5
end

local function header(word, font, stars)
  lcd.drawFilledRectangle(0, 0, 128, 9, BLACK)
  for i = 1, #PILL do
    local r = PILL[i]
    hl(r[2], r[3], r[1], WHITE)
    hl(127 - r[3], 127 - r[2], r[1], WHITE)
  end
  for c = 1, #CHEVRON_X do
    local b = CHEVRON_X[c]
    for r = 1, 7 do
      local x1 = b + CHEVRON[2 * r - 1]
      local x2 = b + CHEVRON[2 * r]
      hl(x1, x2, r, WHITE)
      hl(127 - x2, 127 - x1, r, WHITE)
    end
  end
  local w = textw(font, word)
  local left = 64 - math.floor(w / 2)
  if stars and w <= 30 then
    sprite(left - 8, 2, STAR, WHITE)
    sprite(left + w + 3, 2, STAR, WHITE)
  end
  text(font, left, font == HD and 1 or 2, word, WHITE)
end

local function blocks(pct, show)
  local lit = round(clamp(pct, 0, 100) * 7 / 100)
  for i = 1, 7 do
    local x, w = BLOCK_X[i], BLOCK_W[i]
    if i <= lit then
      if show then lcd.drawFilledRectangle(x, 28, w, 6, BLACK) end
    else
      hl(x, x + w - 1, 28, BLACK)
      hl(x, x + w - 1, 33, BLACK)
    end
  end
end

local function thrText(thr)
  local p = round(thr * 100)
  if p > 0 then return "+" .. p .. "%" end
  return p .. "%"
end

local function init()
  txName = pick(TX_SRC)
  rxName = pick(RX_SRC)
  lqName = pick(LQ_SRC)
  lqMinName = pick(LQ_MIN_SRC)
  pwrName = pick(TPWR_SRC)
  rssiName = pick(RSSI_SRC)
  potName = pick(LIMIT_SRC)
  armName = pick(ARM_SRC)
  thrTrimName = pick(THR_TRIM_SRC)
  rudTrimName = pick(RUD_TRIM_SRC)
  armedText, armedFont = fitName(string.upper(ARMED_TEXT))
  safeText, safeFont = fitName(string.upper(SAFE_TEXT))
  noLinkText, noLinkFont = fitName(string.upper(NO_LINK_TEXT))
end

local function readLink()
  local rxRaw = getValue(rxName) or 0
  local lq = getValue(lqName) or 0
  local lqMin = getValue(lqMinName) or 0
  local tpwr = getValue(pwrName) or 0
  local rssi = getValue(rssiName) or 0
  local ok = (rssi ~= 0) or (lq ~= 0) or (rxRaw ~= 0)
  if ok then
    link.had = true
    link.lostAt = nil
    link.rxRaw, link.lq, link.lqMin, link.tpwr, link.rssi = rxRaw, lq, lqMin, tpwr, rssi
  elseif link.had and not link.lostAt then
    link.lostAt = getTime()
  end
  return ok
end

local function lostText()
  local s = math.floor((getTime() - link.lostAt) / 100)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function trimUnit(name, sign)
  local v = getValue(name) or 0
  return clamp(v * sign / 1024, -1, 1)
end

local function background()
  readLink()
end

local function run(event)
  lcd.clear()
  local blinkTicks = math.max(1, math.floor(BLINK_TIME * 100))
  local blinkOn = (getTime() % blinkTicks) < blinkTicks * BLINK_ON

  local info = model.getInfo()
  local name = string.upper((info and info.name) or "")
  if name == "" then name = "MODEL" end
  local nameFont
  name, nameFont = fitName(name)

  local cap = limitPct()
  local thr = outputUnit(THR_OUT, THR_SIGN)
  local rud = outputUnit(RUD_OUT, RUD_SIGN)
  local armed = isArmed()

  local tx = getValue(txName) or 0
  if tx > 20 then tx = tx / 10 end
  local txP = txPct(tx)
  local txShow = txP >= TX_WARN or blinkOn

  local ok = readLink()
  local have = ok or link.had
  local live = ok or blinkOn
  local lq = clamp(round(link.lq), 0, 100)
  local lqMin = clamp(round(link.lqMin), 0, 100)
  local tpwr = round(link.tpwr)
  local rssi = round(link.rssi)

  local rxV, rxP
  if have and link.rxRaw > 0.5 then
    rxV = asPack(link.rxRaw)
    rxP = lipoPct(rxV)
  end
  local rxShow = (rxP == nil) or (ok and rxP >= RX_WARN) or blinkOn

  local bannerTicks = math.max(1, math.floor(BANNER_TIME * 100))
  local phase = math.floor(getTime() / bannerTicks) % 2
  if not ok then
    if link.lostAt and phase == 1 then
      header(lostText(), HD, true)
    else
      header(noLinkText, noLinkFont, true)
    end
  elseif armed then
    header(armedText, armedFont, true)
  elseif not SHOW_NAME or phase == 0 then
    header(safeText, safeFont, true)
  else
    header(name, nameFont, false)
  end
  vl(41, 9, 61, BLACK)
  vl(88, 9, 61, BLACK)

  sprite(0, 10, RADIO, BLACK)
  if txShow then
    local s = txP .. "%"
    text(F7, 39 - textw(F7, s), 11, s, BLACK)
  end
  battery(20, txP, txShow)
  text(F7, 0, 28, string.format("%.2fV", tx), BLACK)

  sprite(0, 39, SIDE, BLACK)
  if rxP then
    if rxShow then
      local s = rxP .. "%"
      text(F7, 39 - textw(F7, s), 38, s, BLACK)
    end
    battery(47, rxP, rxShow)
    if live then text(F7, 0, 55, string.format("%.2fV", rxV), BLACK) end
  else
    text(F7, 39 - textw(F7, "--"), 38, "--", BLACK)
    battery(47, 0, false)
    text(F7, 0, 55, "--", BLACK)
  end

  throttleGauge(thr, trimUnit(thrTrimName, THR_TRIM_SIGN))
  capGauge(cap)
  drawBoat(thr, rud)
  local stamp = thrText(thr)
  text(F7, 65 - math.floor(textw(F7, stamp) / 2), 48, stamp, BLACK)
  rudderBar(rud, trimUnit(rudTrimName, RUD_TRIM_SIGN))

  local lqShow = (ok and lq >= LQ_WARN) or blinkOn
  if have then
    if lqShow then
      local x = 90
      local s = tostring(lq)
      for i = 1, #s do
        local g = BIG[string.sub(s, i, i)]
        sprite(x, 11, g, BLACK)
        x = x + compile(g).w + 1
      end
      text(F7, x + 1, 18, "%", BLACK)
    end
  else
    sprite(90, 11, BIG["-"], BLACK)
    sprite(100, 11, BIG["-"], BLACK)
  end
  sprite(90, 27, LQ_LABEL, BLACK)
  blocks(have and lq or 0, lqShow)
  hl(89, 127, 35, BLACK)

  local minS = have and tostring(lqMin) or "--"
  local minLine = "Min. LQ: " .. minS
  if textw(F6, minLine) > 38 then minLine = "Min.LQ:" .. minS end
  if (not have) or (ok and lqMin >= LQ_MIN_WARN) or blinkOn then
    text(F6, 90, 38, minLine, BLACK)
  end

  sprite(90, 47, PWR_ICON, BLACK)
  local pwrLine = (have and tostring(tpwr) or "--") .. "mW"
  if (not have) or live then
    text(F7, math.min(97, 128 - textw(F7, pwrLine)), 47, pwrLine, BLACK)
  end

  local rssiLine = "RSSI: " .. (have and tostring(rssi) or "--")
  local rssiX = 96
  if 96 + textw(F6, rssiLine) > 128 then
    rssiX = 90
  else
    sprite(90, 55, RSSI_ICON, BLACK)
  end
  if (not have) or live then text(F6, rssiX, 56, rssiLine, BLACK) end
  return 0
end

return { init = init, run = run, background = background }
