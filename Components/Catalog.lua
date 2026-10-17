-- Bagshui Catalog
-- Exposes: BsCatalog (and Bagshui.components.Catalog)
--
-- Account-wide index of all characters' inventories.
-- Everything is calculated at runtime from what's in SavedVariables.
--
-- Init() takes care of calculations for character other than the current one,
-- while Update() handles the current character and grand totals.

Bagshui:AddComponent(function()
  Bagshui:AddConstants({
    BS_CATALOG_LOCATIONS = {
      EQUIPPED = "Equipped", -- This needs to match the Abbrev_[value] localization.
      MONEY = "$$$",
    },
  })

  -- Table key for totals and prefix for subtotals.
  local TOTAL_KEY = "==Total"

  -- Per-list lookup of itemStrings already present, used by `Catalog:AddToItemTable()`.
  -- Weak keys so lists that go away don't leak their lookups.
  local uniqueItemLookups = setmetatable({}, { __mode = "k" })
  -- Stand-in table key for items that have no itemString (tables can't use nil as a key).
  local NIL_ITEM_STRING_KEY = "==NoItemString"

  -- Money storage.
  local MONEY_ITEM = {
    itemString = BS_CATALOG_LOCATIONS.MONEY,
    count = 0,
  }

  -- Cross-account sharing.
  -- Addons can't read another account's SavedVariables, but Nampower provides
  -- `WriteCustomFile()`/`ReadCustomFile()` for a `CustomData` folder that every client launched
  -- from this installation shares. Each character writes one file with the parts of its data the
  -- Catalog needs, and every character reads the others' files at startup.
  local SHARED_FILE_PREFIX = "Bagshui_"
  local SHARED_ROSTER_FILE = "Bagshui_roster.txt"
  -- Minimum seconds between writes of the current character's file (a final write always happens at logout).
  local SHARED_WRITE_MIN_INTERVAL = 60
  -- Separates the compact Catalog data from the full inventory data in a character's file.
  -- The full inventory is only parsed when someone actually views that character's bags.
  -- (No newlines in the marker in case the file gets line-ending conversion.)
  local SHARED_INVENTORY_MARKER = "--[[BAGSHUI_INVENTORY_SECTION]]"
  -- `info` properties that are shared.
  local SHARED_INFO_KEYS = {
    "name", "realm", "class", "faction", "level", "race",
    "localizedClass", "localizedFaction", "localizedRace", "money",
  }

  --- Are Nampower's file functions available?
  ---@return boolean
  local function sharedFilesAvailable()
    return type(_G.WriteCustomFile) == "function" and type(_G.ReadCustomFile) == "function"
  end

  --- File name for a character's shared data.
  ---@param characterId string
  ---@return string
  local function sharedFileName(characterId)
    return SHARED_FILE_PREFIX .. (string.gsub(characterId, "[^%w]", "_")) .. ".txt"
  end

  --- Reduce an item to the few properties the Catalog uses.
  ---@param item table?
  ---@return table?
  local function compactItem(item)
    if type(item) ~= "table" or item.emptySlot == 1 or not item.itemString or (item.count or 0) < 1 then
      return nil
    end
    return {
      id = item.id,
      itemString = item.itemString,
      itemLink = item.itemLink,
      count = item.count,
      name = item.name,
      texture = item.texture,
      quality = item.quality,
    }
  end

  --- Escape a string for use between double quotes in Lua source.
  --- Unlike `BsUtil.Serialize()` this also handles newlines (item tooltips contain them)
  --- and other control characters, which would otherwise make the shared file unreadable.
  ---@param str string
  ---@return string
  local function escapeSharedString(str)
    str = string.gsub(str, "\\", "\\\\")
    str = string.gsub(str, '"', '\\"')
    str = string.gsub(str, "\n", "\\n")
    str = string.gsub(str, "\r", "\\r")
    str = string.gsub(str, "%c", function(c)
      return string.format("\\%03d", string.byte(c))
    end)
    return str
  end

  --- Append the Lua source for a table to `parts`. Only strings, numbers, booleans and
  --- tables are written; anything else (and nan/infinite numbers) is skipped.
  ---@param tbl table
  ---@param parts string[]
  ---@param depth number
  local function serializeSharedTable(tbl, parts, depth)
    table.insert(parts, "{")
    if depth < 20 then
      for key, value in pairs(tbl) do
        local keyType = type(key)
        local valueType = type(value)
        if
          (keyType == "string" or keyType == "number")
          and (valueType == "string" or valueType == "number" or valueType == "boolean" or valueType == "table")
          and not (valueType == "number" and (value ~= value or value == 1 / 0 or value == -1 / 0))
          and not (keyType == "number" and (key ~= key or key == 1 / 0 or key == -1 / 0))
        then
          if keyType == "string" then
            table.insert(parts, '["' .. escapeSharedString(key) .. '"]=')
          else
            table.insert(parts, "[" .. tostring(key) .. "]=")
          end
          if valueType == "table" then
            serializeSharedTable(value, parts, depth + 1)
          elseif valueType == "string" then
            table.insert(parts, '"' .. escapeSharedString(value) .. '"')
          else
            table.insert(parts, tostring(value))
          end
          table.insert(parts, ",")
        end
      end
    end
    table.insert(parts, "}")
  end

  --- Serialize a table to Lua source that `BsUtil.Deserialize()` can read back.
  ---@param tbl table
  ---@return string
  local function serializeShared(tbl)
    local parts = {}
    serializeSharedTable(tbl, parts, 0)
    return table.concat(parts)
  end

  --- Lua source for a table key (`["name"]=` or `[1]=`), or `nil` if the key can't be shared.
  ---@param key string|number
  ---@return string?
  local function sharedKeyText(key)
    if type(key) == "string" then
      return '["' .. escapeSharedString(key) .. '"]='
    elseif type(key) == "number" and key == key and key ~= 1 / 0 and key ~= -1 / 0 then
      return "[" .. tostring(key) .. "]="
    end
    return nil
  end

  --- Lua source for a single value, or `nil` if the value can't be shared.
  ---@param value any
  ---@return string?
  local function sharedValueText(value)
    local valueType = type(value)
    if valueType == "table" then
      return serializeShared(value)
    elseif valueType == "string" then
      return '"' .. escapeSharedString(value) .. '"'
    elseif valueType == "boolean" then
      return tostring(value)
    elseif valueType == "number" and value == value and value ~= 1 / 0 and value ~= -1 / 0 then
      return tostring(value)
    end
    return nil
  end

  -- Key suffixes for subtotals.
  local SUBTOTAL_TYPE = {
    Current = "Current",
    Other = "Other",
  }

  -- How much to indent each tooltip line.
  local TOOLTIP_INDENT = BS_INDENT

  local Catalog = {
    -- Array of the item info tables of all items on the account, sorted by name.
    items = {},

    -- Calculation results as produced by `BuildIndex()` and `Update()`.
    -- Structure:
    -- ```
    -- {
    --  	-- Overall account-wide totals.
    --  	["==Total"] = { <itemString> => <count> },
    --  	-- Current character totals (will be the same as the realm-level total, obviously).
    --  	["==TotalCurrent"] = { <itemString> => <count> },
    --  	-- Other character totals.
    --  	["==TotalOther"] = { <itemString> => <count> },
    --  	-- Each realm will have an entry.
    --  	["realm1"] = {
    --  		-- Overall realm-wide totals.
    --  		["==Total"] = { <itemString> => <count> },
    --  		-- Current character realm-level totals.
    --  		["==TotalCurrent"] = { <itemString> => <count> },
    --  		-- Other character realm-level totals.
    --  		["==TotalOther"] = { <itemString> => <count> },
    --  		-- Class-colored character name with faction appended.
    --  		["_formattedCharacterNames"] = { <characterName> => <formattedCharacterName> },
    --  		-- Characters on this realm, sorted alphabetically.
    --  		["_sortedCharacterList"] = { "characterName1", "characterName2", ... },
    --  		-- Each character will have an entry.
    --  		["characterName1"] = { <itemString> => <count> },
    --  	},
    -- }
    -- ```
    totals = {},

    -- Arrays of item tables that can later be iterated during calculations of totals.
    -- There isn't an `all` entry here because that's `self.items`.
    itemListTables = {
      currentCharacter = {},
      otherCharacter = {},
    },

    -- Array of locations where items are stored (BS_INVENTORY_TYPE_UI_ORDER followed by EQUIPPED).
    -- Iterated to build per-character tooltips.
    itemLocations = {},

    -- List of realms, sorted alphabetically.
    sortedRealmList = {},

    -- Reusable table for calculating per-location totals for each character.
    -- ```
    -- {
    --  	<itemLocation> = { <itemString> => <count> }
    -- }
    -- ```
    tempItemCounts = {},

    -- Tooltips for items from other characters need to be reloaded during `Update()`.
    tooltipUpdateNeeded = true,

    -- Has `Init()` finished?
    initialized = false,
  }
  Bagshui.environment.BsCatalog = Catalog
  Bagshui.components.Catalog = Catalog

  --- Event processing.
  ---@param event string WoW API event
  ---@param arg1 any First event argument.
  function Catalog:OnEvent(event, arg1)
    -- Bagshui:PrintDebug("Catalog event " .. event)

    -- Initial processing at startup. Delayed since it's not needed immediately.
    -- Other update events are allowed to delay initial processing even further.
    if event == "PLAYER_ENTERING_WORLD" or not self.initialized then
      -- This check is duplicated in Catalog:Init() but let's be extra safe.
      if not self.initialized then
        Bagshui:QueueClassCallback(self, self.Init, 3)
      end
      return
    end

    if event == "BAGSHUI_CHARACTER_UPDATE" then
      -- Refresh the current character's name as we may now have more data.
      self:StoreFormattedCharacterName(Bagshui.currentCharacterId, Bagshui.currentCharacterData.info)
      return
    end

    if event == "BAGSHUI_CHARACTER_LEARNED_RECIPE" then
      -- Learning a new recipe requires updating tooltips for items from other characters.
      self.tooltipUpdateNeeded = true
    end

    if event == "BAGSHUI_CATALOG_SHOULD_UPDATE" then
      -- We've received the delayed event to trigger the update.
      self:Update()
      return
    end

    -- Any other event requires an update after a delay.
    Bagshui:QueueEvent("BAGSHUI_CATALOG_SHOULD_UPDATE", 0.75)
  end

  --- Initialize the Catalog class.
  --- Also calculates item totals for all characters other than the current one.
  function Catalog:Init()
    -- Bagshui:PrintDebug("Catalog Init()")

    -- Safeguard just in case. Without this, if Init() is called multiple times
    -- then the list of characters will be duplicated and tooltips will look weird.
    if self.initialized then
      return
    end

    -- Initialize storage tables.

    for _, inventoryType in ipairs(BS_INVENTORY_TYPE_UI_ORDER) do
      table.insert(self.itemLocations, inventoryType)
    end
    for _, itemLocation in pairs(BS_CATALOG_LOCATIONS) do
      table.insert(self.itemLocations, itemLocation)
    end

    for _, inventoryType in ipairs(self.itemLocations) do
      self.tempItemCounts[inventoryType] = {}
    end

    self:CreateTotalKeys(self.totals)

    -- Process one character: register it in the realm lists and, if it isn't the
    -- current character, calculate its totals.
    local function processCharacter(characterId, data)
      -- Make sure it's a fully formed character.
      if data.info and data.info.name and data.info.realm then
        local realm = data.info.realm

        -- Initialize realm storage table.
        if not self.totals[realm] then
          table.insert(self.sortedRealmList, realm)
          self.totals[realm] = {
            _sortedCharacterList = {},
            _formattedCharacterNames = {},
          }
          self:CreateTotalKeys(self.totals[realm])
        end

        -- Store data about this character that will be needed later.
        table.insert(self.totals[realm]._sortedCharacterList, data.info.name)
        self:StoreFormattedCharacterName(characterId, data.info)

        -- Update() will take calculations for the current character, so Init() only needs to handle others.
        if characterId ~= Bagshui.currentCharacterId then
          self:CalculatePerCharacterTotal(characterId, data, self.itemListTables.otherCharacter)
        end
      end
    end

    -- Read characters from other accounts (if Nampower's file functions are available).
    self:LoadSharedCharacters()

    -- Process all characters in SavedVariables.
    for characterId, data in pairs(Bagshui.characters) do
      processCharacter(characterId, data)
    end

    -- Process characters from other accounts on this computer (see `Bagshui.sharedCharacters`).
    -- A pcall keeps one malformed shared character from breaking the whole Catalog.
    for characterId, data in pairs(Bagshui.sharedCharacters) do
      if not getmetatable(data) and BsCharacterData and BsCharacterData.objectMetatable then
        setmetatable(data, BsCharacterData.objectMetatable)
      end
      local ok, err = pcall(processCharacter, characterId, data)
      if not ok then
        Bagshui:PrintDebug("Skipping shared character " .. tostring(characterId) .. ": " .. tostring(err))
      end
    end

    -- Ensure all items are known so tooltips will load immediately.
    -- This used to run inside the character loop above, which re-loaded every previously
    -- processed character's items again for each additional character (a hidden tooltip
    -- load per item), so the cost grew with characters x items.
    for _, item in ipairs(self.itemListTables.otherCharacter) do
      BsItemInfo:LoadItemIntoLocalGameCache(item.itemString)
    end

    -- Produce subtotals for all characters other than the current one.
    self:CalculateSubtotals(self.itemListTables.otherCharacter, SUBTOTAL_TYPE.Other)

    -- Character and realm lists only need to be sorted once because they can't change without logging out.
    table.sort(self.sortedRealmList)
    for _, realm in ipairs(self.sortedRealmList) do
      table.sort(self.totals[realm]._sortedCharacterList)
    end

    -- Get current character data and calculate totals.
    self:Update()

    -- Register slash command.
    BsSlash:AddOpenCloseHandler("Catalog", self)

    -- Allow events to be processed normally.
    self.initialized = true
  end

  --- Add this character to the shared roster, once per session.
  --- Lua can't list a directory, so the roster is how other characters find our file.
  function Catalog:JoinSharedRoster()
    if self.joinedSharedRoster then
      return
    end
    self.joinedSharedRoster = true

    local rosterLine = "R~" .. Bagshui.currentCharacterId
    local ok, roster = pcall(_G.ReadCustomFile, SHARED_ROSTER_FILE)
    if ok and type(roster) == "string" then
      for line in string.gfind(roster, "[^\n]+") do
        if BsUtil.Trim(line) == rosterLine then
          return
        end
      end
    end
    -- Appended (not rewritten) because several clients may start at the same moment.
    pcall(_G.WriteCustomFile, SHARED_ROSTER_FILE, rosterLine .. "\n", "a")
  end

  --- Write the current character's Catalog data where characters on other accounts can read it.
  --- Rate limited; `force` skips the limit (used at logout).
  ---@param force boolean?
  function Catalog:WriteSharedCharacter(force)
    if not sharedFilesAvailable() then
      return
    end

    -- Wait until the character's basic info has been filled in.
    local currentInfo = Bagshui.currentCharacterData.info
    if not currentInfo or not currentInfo.name or currentInfo.name == "" or not currentInfo.realm or currentInfo.realm == "" then
      return
    end

    local now = _G.time()
    if not force and self.lastSharedWrite and (now - self.lastSharedWrite) < SHARED_WRITE_MIN_INTERVAL then
      self.sharedWritePending = true
      return
    end

    -- The work is split into small steps that run one per frame, so building and serializing a big
    -- bank doesn't freeze the game for a moment. (At logout everything runs at once.)
    if self.sharedWriteJob then
      if not force then
        return
      end
      self.sharedWriteJob = nil
    end

    self.lastSharedWrite = now
    self.sharedWritePending = false

    local data = Bagshui.currentCharacterData
    local record = {
      version = BS_DATA_VERSION,
      id = Bagshui.currentCharacterId,
      info = {},
    }
    local catalogBody
    -- pieces[storageKey][field] = array of serialized "[key]=value," strings (or a single string for non-tables).
    local pieces = {}
    local steps = {}

    -- Basic info and equipped items.
    table.insert(steps, function()
      local info = data.info or {}
      for _, key in ipairs(SHARED_INFO_KEYS) do
        record.info[key] = info[key]
      end
      record.info.equipped = {}
      if type(info.equipped) == "table" then
        for slot, item in pairs(info.equipped) do
          local compacted = compactItem(item)
          if compacted then
            record.info.equipped[slot] = compacted
          end
        end
      end
    end)

    -- Bags, bank, etc. for the Catalog. Empty slots are dropped, so each bag becomes a dense array.
    for _, inventoryType in pairs(BS_INVENTORY_TYPE) do
      local storageKey = BsUtil.LowercaseFirstLetter(inventoryType)
      table.insert(steps, function()
        if data[storageKey] and data[storageKey].inventory then
          local bagsOut = {}
          for bagNum, contents in pairs(data[storageKey].inventory) do
            local list = {}
            for _, item in ipairs(contents) do
              local compacted = compactItem(item)
              if compacted then
                table.insert(list, compacted)
              end
            end
            bagsOut[bagNum] = list
          end
          record[storageKey] = { inventory = bagsOut }
        end
      end)
    end

    table.insert(steps, function()
      catalogBody = serializeShared(record)
    end)

    -- Full inventory (every slot plus bag info) so other accounts can view this character's bags.
    -- Serialized one bag at a time; it reads the live saved tables, nothing is copied.
    for _, inventoryType in pairs(BS_INVENTORY_TYPE) do
      local storageKey = BsUtil.LowercaseFirstLetter(inventoryType)
      local stored = data[storageKey]
      if type(stored) == "table" then
        pieces[storageKey] = {}
        for _, fieldName in ipairs({ "inventory", "containers", "neverOnline" }) do
          -- Lua 5.0 doesn't give closures their own copy of `for` loop variables, so copy
          -- everything the delayed steps use into locals declared inside the loop body.
          local field = fieldName
          local value = stored[field]
          if type(value) == "table" then
            pieces[storageKey][field] = {}
            for loopKey in pairs(value) do
              local subKey = loopKey
              table.insert(steps, function()
                local current = data[storageKey] and data[storageKey][field]
                local subValue = type(current) == "table" and current[subKey] or nil
                local keyText = sharedKeyText(subKey)
                local valueText = subValue ~= nil and sharedValueText(subValue) or nil
                if keyText and valueText then
                  table.insert(pieces[storageKey][field], keyText .. valueText .. ",")
                end
              end)
            end
          elseif value ~= nil then
            pieces[storageKey][field] = sharedValueText(value)
          end
        end
      end
    end

    -- Put it all together and write it.
    table.insert(steps, function()
      local inventoryParts = { "{" }
      for storageKey, fields in pairs(pieces) do
        table.insert(inventoryParts, sharedKeyText(storageKey) .. "{")
        for field, content in pairs(fields) do
          local valueText
          if type(content) == "table" then
            valueText = "{" .. table.concat(content) .. "}"
          else
            valueText = content
          end
          if valueText then
            table.insert(inventoryParts, sharedKeyText(field) .. valueText .. ",")
          end
        end
        table.insert(inventoryParts, "},")
      end
      table.insert(inventoryParts, "}")

      local body = catalogBody .. "\n" .. SHARED_INVENTORY_MARKER .. "\n" .. table.concat(inventoryParts)

      -- Skip the write if nothing changed.
      if body == self.lastSharedBody then
        return
      end

      self:JoinSharedRoster()
      local written = pcall(_G.WriteCustomFile, sharedFileName(Bagshui.currentCharacterId), "-- " .. now .. "\n" .. body, "w")
      if written then
        self.lastSharedBody = body
      end
    end)

    local job = { steps = steps, index = 1 }
    local function runStep()
      local step = job.steps[job.index]
      job.index = job.index + 1
      local ok, err = pcall(step)
      if not ok then
        Bagshui:PrintDebug("Could not write shared character data: " .. tostring(err))
        job.index = getn(job.steps) + 1
      end
    end

    if force then
      while job.index <= getn(job.steps) do
        runStep()
      end
      return
    end

    self.sharedWriteJob = job
    if not self.sharedWriteFrame then
      self.sharedWriteFrame = _G.CreateFrame("Frame")
    end
    self.sharedWriteFrame:SetScript("OnUpdate", function()
      if self.sharedWriteJob ~= job then
        -- Replaced by a forced write at logout.
        this:SetScript("OnUpdate", nil)
        return
      end
      if job.index <= getn(job.steps) then
        runStep()
      end
      if job.index > getn(job.steps) then
        self.sharedWriteJob = nil
        this:SetScript("OnUpdate", nil)
      end
    end)
  end

  --- Read the characters other accounts have shared and put them in `Bagshui.sharedCharacters`.
  --- Characters in this account's own SavedVariables always take priority.
  function Catalog:LoadSharedCharacters()
    BsUtil.TableClear(Bagshui.sharedCharacters)
    if not sharedFilesAvailable() then
      return
    end

    local ok, roster = pcall(_G.ReadCustomFile, SHARED_ROSTER_FILE)
    if not ok or type(roster) ~= "string" then
      return
    end

    for line in string.gfind(roster, "[^\n]+") do
      local _, _, characterId = string.find(BsUtil.Trim(line), "^R~(.+)$")
      if
        characterId
        and characterId ~= Bagshui.currentCharacterId
        and not Bagshui.characters[characterId]
        and not Bagshui.sharedCharacters[characterId]
      then
        local readOk, text = pcall(_G.ReadCustomFile, sharedFileName(characterId))
        if readOk and type(text) == "string" and text ~= "" then
          -- Only the compact Catalog section is parsed here; see `Catalog:LoadSharedInventory()`.
          local catalogText = text
          local markerStart = string.find(text, SHARED_INVENTORY_MARKER, 1, true)
          if markerStart then
            catalogText = string.sub(text, 1, markerStart - 1)
          end
          local parseOk, record = pcall(BsUtil.Deserialize, catalogText)
          if
            parseOk
            and type(record) == "table"
            and record.version == BS_DATA_VERSION
            and type(record.info) == "table"
            and type(record.info.name) == "string"
            and type(record.info.realm) == "string"
          then
            -- Fill in any properties the file doesn't carry, the same way Bagshui does for its own saved items.
            for _, inventoryType in pairs(BS_INVENTORY_TYPE) do
              local storageKey = BsUtil.LowercaseFirstLetter(inventoryType)
              if type(record[storageKey]) == "table" and type(record[storageKey].inventory) == "table" then
                for _, contents in pairs(record[storageKey].inventory) do
                  for _, item in ipairs(contents) do
                    BsItemInfo:InitializeItem(item, false, true)
                  end
                end
              end
            end
            if type(record.info.equipped) == "table" then
              for _, item in pairs(record.info.equipped) do
                BsItemInfo:InitializeItem(item, false, true)
              end
            end
            -- Last time the character's file was written (shown in the Character Data manager).
            local _, _, writtenAt = string.find(text, "^%-%- (%d+)")
            record.lastLogout = tonumber(writtenAt)
            Bagshui.sharedCharacters[characterId] = record
          else
            Bagshui:PrintDebug("Ignoring shared character file for " .. characterId)
          end
        end
      end
    end

    -- Let the Character Data manager list them too.
    if BsCharacterData and BsCharacterData.RefreshList then
      BsCharacterData:RefreshList()
      BsCharacterData:Update()
    end
  end

  --- Load a shared character's full inventory (all slots and bag info) from its file so it
  --- can be viewed in a Bagshui window. Replaces the compact Catalog data in the character's record.
  ---@param characterId string
  ---@return boolean loaded
  ---@return string? reason Why loading failed.
  function Catalog:LoadSharedInventory(characterId)
    local record = Bagshui.sharedCharacters[characterId]
    if not record or not sharedFilesAvailable() then
      return false, "not a shared character, or Nampower's file functions are missing"
    end

    -- Docked windows ask for the same character back to back, so don't read the file twice.
    if record.inventoryLoadedAt and (_G.GetTime() - record.inventoryLoadedAt) < 5 then
      return true
    end

    local readOk, text = pcall(_G.ReadCustomFile, sharedFileName(characterId))
    if not readOk or type(text) ~= "string" or text == "" then
      return false, "its shared file could not be read"
    end
    local _, markerEnd = string.find(text, SHARED_INVENTORY_MARKER, 1, true)
    if not markerEnd then
      return false, "its inventory hasn't been shared yet. Log in on that character (on its own account) with this version of Bagshui once"
    end
    local parseOk, inventoryRecord = pcall(BsUtil.Deserialize, string.sub(text, markerEnd + 1))
    if not parseOk or type(inventoryRecord) ~= "table" then
      return false, "its shared inventory couldn't be read (it was probably saved by an older version). Log in on that character once with this version of Bagshui"
    end

    for _, inventoryType in pairs(BS_INVENTORY_TYPE) do
      local storageKey = BsUtil.LowercaseFirstLetter(inventoryType)
      local stored = inventoryRecord[storageKey]
      if type(stored) == "table" then
        stored.inventory = type(stored.inventory) == "table" and stored.inventory or {}
        stored.containers = type(stored.containers) == "table" and stored.containers or {}
        -- Empty tables aren't serialized, so make sure every bag has an inventory table.
        for bagNum, _ in pairs(stored.containers) do
          if type(stored.inventory[bagNum]) ~= "table" then
            stored.inventory[bagNum] = {}
          end
        end
        for _, contents in pairs(stored.inventory) do
          for _, item in ipairs(contents) do
            BsItemInfo:InitializeItem(item, false, true)
          end
        end
        record[storageKey] = stored
      end
    end

    record.inventoryLoadedAt = _G.GetTime()
    return true
  end

  --- Stop sharing a character: blank its file and remove it from the roster.
  --- Called when a character is deleted from the Character Data manager.
  ---@param characterId string
  function Catalog:ForgetSharedCharacter(characterId)
    if not sharedFilesAvailable() then
      return
    end

    pcall(_G.WriteCustomFile, sharedFileName(characterId), "", "w")

    local ok, roster = pcall(_G.ReadCustomFile, SHARED_ROSTER_FILE)
    if ok and type(roster) == "string" then
      local rosterLine = "R~" .. characterId
      local remaining = ""
      for line in string.gfind(roster, "[^\n]+") do
        line = BsUtil.Trim(line)
        if line ~= rosterLine then
          remaining = remaining .. line .. "\n"
        end
      end
      pcall(_G.WriteCustomFile, SHARED_ROSTER_FILE, remaining, "w")
    end
  end

  --- Sort an array of item tables alphabetically by name.
  ---@param a table
  ---@param b table
  ---@return boolean
  local function sortItemList(a, b)
    return (a.name or "") < (b.name or "")
  end

  --- Refresh item counts and totals for the current character, then refresh overall totals.
  function Catalog:Update()
    -- Bagshui:PrintDebug("Catalog:Update() - tooltips? " .. tostring(self.tooltipUpdateNeeded))

    -- Reset existing grand totals and current character subtotals.
    BsUtil.TableClear(self.totals[TOTAL_KEY])
    for _, realm in ipairs(self.sortedRealmList) do
      BsUtil.TableClear(self.totals[realm][TOTAL_KEY])
    end
    BsUtil.TableClear(self.totals[self:TotalKey(SUBTOTAL_TYPE.Current)])
    for _, realm in ipairs(self.sortedRealmList) do
      BsUtil.TableClear(self.totals[realm][self:TotalKey(SUBTOTAL_TYPE.Current)])
    end

    -- Wipe the item tracking table so `AddToItemTable()` will work.
    BsUtil.TableClear(self.itemListTables.currentCharacter)

    -- Get the item counts for the current character.
    self:CalculatePerCharacterTotal(
      Bagshui.currentCharacterId,
      Bagshui.currentCharacterData,
      self.itemListTables.currentCharacter
    )

    -- Calculate subtotals for current character.
    self:CalculateSubtotals(self.itemListTables.currentCharacter, SUBTOTAL_TYPE.Current)

    -- Build unique, sorted list of all items on the account.
    BsUtil.TableClear(self.items)
    for _, itemTable in pairs(self.itemListTables) do
      for _, item in ipairs(itemTable) do
        if type(item.id) == "number" and item.id > 0 then
          -- Refresh the tooltip for items belonging to other characters so
          -- the Catalog will accurately indicate whether the current
          -- character can use the item.
          if self.tooltipUpdateNeeded and itemTable ~= self.itemListTables.currentCharacter then
            -- 3nd parameter: Force tooltip loading to use itemString
            -- instead of bagNum/slotNum, since those are for other
            -- characters in this context and will lead to pulling
            -- the wrong tooltip.
            BsItemInfo:GetTooltip(item, nil, true)
          end
          self:AddToItemTable(item, self.items)
        end
      end
    end
    table.sort(self.items, sortItemList)

    -- Combine totals from current character and other characters.
    self:CalculateGrandTotals()

    -- Refresh the account-wide search if it's visible.
    if self.objectManager and self.objectManager.uiFrame:IsVisible() then
      self.objectManager:UpdateList()
    end

    -- Reset flag.
    self.tooltipUpdateNeeded = false

    -- Share the current character with other accounts.
    self:WriteSharedCharacter()
  end

  --- Iterate a character's item storage locations and collect sums of each item.
  --- Totals are calculated at the item, character, and realm level.
  ---@param characterId string Unique ID of the character being analyzed. This is generated by Bagshui on startup and housed in the `Bagshui.currentCharacterId` property. It is also the key for each character in the SavedVariables `characters` table.
  ---@param characterData table Character's table from the SavedVariables `characters` table.
  ---@param itemTable table Array that will be filled with the unique list of all items belonging to this character.
  function Catalog:CalculatePerCharacterTotal(characterId, characterData, itemTable)
    assert(type(characterData) == "table", "Catalog:CalculatePerCharacterTotal() - characterData must be a table")
    assert(
      type(characterData.realm) == "string",
      "Catalog:CalculatePerCharacterTotal() - characterData.realm is required"
    )

    local storage = self.totals[characterData.info.realm]
    local storageSuffix = (characterId == Bagshui.currentCharacterId and SUBTOTAL_TYPE.Current or SUBTOTAL_TYPE.Other)

    BsUtil.TableClear(storage[self:TotalKey(characterData.info.name)]) -- Reset the storage for this character.
    for _, inventoryType in ipairs(self.itemLocations) do
      BsUtil.TableClear(self.tempItemCounts[inventoryType]) -- Used by AddToItemTotal().
    end

    -- Normal inventory locations (Bags, Bank, etc.).
    for _, inventoryType in pairs(BS_INVENTORY_TYPE) do
      local inventoryTypeStorageKey = BsUtil.LowercaseFirstLetter(inventoryType)
      if characterData[inventoryTypeStorageKey] and characterData[inventoryTypeStorageKey].inventory then
        for bagNum, contents in pairs(characterData[inventoryTypeStorageKey].inventory) do
          for slotNum, item in ipairs(contents) do
            if item.emptySlot ~= 1 then
              self:AddItemToSubtotals(
                item,
                storage,
                storageSuffix,
                characterId,
                characterData,
                itemTable,
                inventoryType
              )
            end
          end
        end
      end
    end

    -- Equipped items.
    if type(characterData.info.equipped) == "table" then
      for slot, item in pairs(characterData.info.equipped) do
        self:AddItemToSubtotals(
          item,
          storage,
          storageSuffix,
          characterId,
          characterData,
          itemTable,
          BS_CATALOG_LOCATIONS.EQUIPPED
        )
      end
    end

    -- Money.
    if type(characterData.info.money) == "number" then
      MONEY_ITEM.count = characterData.info.money
      self:AddItemToSubtotals(
        MONEY_ITEM,
        storage,
        storageSuffix,
        characterId,
        characterData,
        itemTable,
        BS_CATALOG_LOCATIONS.MONEY
      )
    end

    -- Instead of building out tooltip strings when the tooltip is requested,
    -- we're just going to pre-build them.
    -- The goal is to come out with something like "Bags: 3" or "Bags: 2 + Bank 5 = 7".

    local tooltipString, multipleLocations, lastCount

    for itemString, totalCount in pairs(storage[self:TotalKey(characterData.info.name)]) do
      tooltipString = ""
      multipleLocations = false

      -- self.itemLocations provides the correct order for the inventory locations.
      for _, inventoryType in ipairs(self.itemLocations) do
        -- tempItemCounts was populated by `AddItemToSubtotals()` during the loops above.
        if self.tempItemCounts[inventoryType][itemString] then
          -- Add a separator if this item is found in more than one location.
          if string.len(tooltipString) > 0 then
            tooltipString = tooltipString .. GRAY_FONT_COLOR_CODE .. " + " .. FONT_COLOR_CODE_CLOSE
            multipleLocations = true
          end

          -- When there are not multiple locations for an item, this information will be used to recolor the number
          -- so that "Bags: 3" has a white 3 just like "Bags: 2 + Bank 5 = 7" will have a white 7.
          lastCount = self.tempItemCounts[inventoryType][itemString]

          if inventoryType == BS_CATALOG_LOCATIONS.MONEY and itemString == BS_CATALOG_LOCATIONS.MONEY then
            -- Money is a little weird in that it's shoehorned into the catalog in a special location that
            -- only contains the money itemString, so when we see it, we know that this is not a tooltip
            -- that needs to be built up from multiple locations; it's just a money string.
            tooltipString = BsUtil.FormatMoneyString(lastCount)
            break
          else
            tooltipString = tooltipString
              .. string.format(L.Symbol_Colon, (L_nil["Abbrev_" .. inventoryType] or L[inventoryType]))
              .. " "
              .. lastCount
          end
        end
      end

      -- Final touches -- either add the sum at the end or recolor the number.
      if multipleLocations then
        tooltipString = tooltipString
          .. GRAY_FONT_COLOR_CODE
          .. " = "
          .. FONT_COLOR_CODE_CLOSE
          .. HIGHLIGHT_FONT_COLOR_CODE
          .. totalCount
          .. FONT_COLOR_CODE_CLOSE
      else
        tooltipString =
          string.gsub(tooltipString, lastCount .. "$", HIGHLIGHT_FONT_COLOR_CODE .. lastCount .. FONT_COLOR_CODE_CLOSE)
      end

      -- Overwrite the existing total count with the tooltip string since we have no other use for the per-character total.
      storage[self:TotalKey(characterData.info.name)][itemString] = tooltipString
    end
  end

  --- Add up per-realm subtotals of a given type into an account-wide subtotal.
  ---@param uniqueItemList table Deduplicated list of items.
  ---@param subtotalType string `SUBTOTAL_TYPE` value.
  function Catalog:CalculateSubtotals(uniqueItemList, subtotalType)
    assert(subtotalType, "Catalog:CalculateSubtotals() - subtotalType is required")
    for _, item in ipairs(uniqueItemList) do
      for _, realm in ipairs(self.sortedRealmList) do
        self:AddToTotal(
          self.totals,
          subtotalType,
          item.itemString,
          self:GetTotal(self.totals[realm], subtotalType, item.itemString)
        )
      end
    end
  end

  --- Combine "current" and "other" character totals into final tallies.
  function Catalog:CalculateGrandTotals()
    for _, subtotalType in pairs(SUBTOTAL_TYPE) do
      for _, realm in ipairs(self.sortedRealmList) do
        for itemString, count in pairs(self.totals[realm][self:TotalKey(subtotalType)]) do
          -- Per-realm grand total.
          self:AddToTotal(self.totals[realm], nil, itemString, count)
          -- Account-wide grand total.
          self:AddToTotal(self.totals, nil, itemString, count)
        end
      end
    end
  end

  --- Primary function called for each item in a character's inventory that is responsible
  --- for adding it to all the various subtotal tables. This is a helper for `CalculatePerCharacterTotal()`
  --- and isn't meant to be called independently because it relies on that function doing
  --- the necessary prep work of clearing tables.
  ---@param item table Bagshui ItemInfo table.
  ---@param storage table Place to store the calculation results.
  ---@param storageSuffix string One of the SUBTOTAL_TYPE values. Controls whether the subtotals are stored in the "Current" or "Other" character bucket.
  ---@param characterId string Unique ID of the character.
  ---@param characterData table Character's table from the SavedVariables `characters` table.
  ---@param uniqueItemList table Array where the deduplicated list of items will be stored (see `AddToItemTable()`).
  ---@param inventoryType string Which location in the `self.tempItemCounts` table this item belongs to.
  function Catalog:AddItemToSubtotals(
    item,
    storage,
    storageSuffix,
    characterId,
    characterData,
    uniqueItemList,
    inventoryType
  )
    if
      type(item) == "table"
      or ((item.id or 0) > 0 or item.itemString == MONEY_ITEM.itemString) and (item.count or 0) > 0
    then
      -- Add to list of known items if not already present.
      -- 3rd parameter: Make a copy of the item table if this item comes from another character's
      -- cached inventory so we can manipulate it (mainly updating tooltips to get usable status)
      -- without messing up their data.
      self:AddToItemTable(item, uniqueItemList, characterId ~= Bagshui.currentCharacterId)
      -- Character total.
      self:AddToTotal(storage, characterData.info.name, item.itemString, item.count)
      -- Inventory-type total.
      self:AddToItemTotal(self.tempItemCounts[inventoryType], item.itemString, item.count)
      -- Overall subtotal.
      self:AddToTotal(storage, storageSuffix, item.itemString, item.count)
    end
  end

  --- Add the given item's itemString to the provided item list table, but only
  --- if it hasn't already been inserted.
  ---@param item table Bagshui ItemInfo table.
  ---@param uniqueItemList any
  function Catalog:AddToItemTable(item, uniqueItemList, copy)
    -- Don't duplicate.
    -- A lookup table of itemStrings per list replaces scanning the whole list for every
    -- insert (which made rebuilding the account-wide list quadratic). The lookup is
    -- rebuilt from the list whenever its recorded size doesn't match, which also covers
    -- lists that were cleared with `BsUtil.TableClear()` or modified elsewhere.
    local lookup = uniqueItemLookups[uniqueItemList]
    local listSize = table.getn(uniqueItemList)
    if not lookup or lookup.size ~= listSize then
      lookup = { size = listSize, itemStrings = {} }
      for _, existingItem in ipairs(uniqueItemList) do
        lookup.itemStrings[existingItem.itemString or NIL_ITEM_STRING_KEY] = true
      end
      uniqueItemLookups[uniqueItemList] = lookup
    end

    local itemStringKey = item.itemString or NIL_ITEM_STRING_KEY
    if lookup.itemStrings[itemStringKey] then
      return
    end

    local itemToInsert = copy and BsUtil.TableCopy(item) or item

    table.insert(uniqueItemList, itemToInsert)
    lookup.itemStrings[itemStringKey] = true
    lookup.size = listSize + 1
  end

  --- Prepare the storage location, then add up the item total.
  ---@param storage table Place to store the calculation results.
  ---@param subtotalType string? `SUBTOTAL_TYPE` value, or `nil` if this is a grand total.
  ---@param itemString string Unique item identifier.
  ---@param count number Amount by which to increase this item's total.
  function Catalog:AddToTotal(storage, subtotalType, itemString, count)
    if type(itemString) ~= "string" or type(count) ~= "number" then
      return
    end

    -- Ensure the storage location exists.
    local keyString = self:TotalKey(subtotalType)
    if not storage[keyString] then
      storage[keyString] = {}
    end

    self:AddToItemTotal(storage[keyString], itemString, count)
  end

  --- Add the given count to the given item's total.
  ---@param storage table Place to store the calculation results. Must be an `{ <itemString> => <count> }` table.
  ---@param itemString string Unique item identifier.
  ---@param count number Amount by which to increase this item's total.
  function Catalog:AddToItemTotal(storage, itemString, count)
    if type(itemString) ~= "string" or type(count) ~= "number" then
      return
    end
    storage[itemString] = (storage[itemString] and storage[itemString] + count or count)
  end

  -- Reusable variable for `GetTotal()`'s key checking.
  local getTotal_key

  --- Pull the calculated total for the given `itemString` from the specified storage location.
  ---@param storage table Calculation results to query.
  ---@param subtotalType string? `SUBTOTAL_TYPE` value, or `nil` to get the grand total.
  ---@param itemString string Unique item identifier.
  ---@return integer count
  function Catalog:GetTotal(storage, subtotalType, itemString)
    getTotal_key = self:TotalKey(subtotalType)
    return storage[getTotal_key] and storage[getTotal_key][itemString] or 0
  end

  --- Prepare the given storage table with keys that are known to be required.
  ---@param storage table Place to create keys.
  function Catalog:CreateTotalKeys(storage)
    if not storage[TOTAL_KEY] then
      storage[TOTAL_KEY] = {}
    end
    for _, suffix in pairs(SUBTOTAL_TYPE) do
      local keyString = self:TotalKey(suffix)
      if not storage[keyString] then
        storage[keyString] = {}
      end
    end
  end

  --- Get the key for the calculation results table of the specified type.
  ---@param subtotalType string? `SUBTOTAL_TYPE` value, or `nil` if this is a grand total.
  ---@return string key
  function Catalog:TotalKey(subtotalType)
    return TOTAL_KEY .. (subtotalType or "")
  end

  --- Build a `<name colored by class> [<colored faction indicator]` string.
  ---@param characterId string Unique character identifier.
  ---@param characterInfo table `info` table from the character's SavedVariables data.
  function Catalog:StoreFormattedCharacterName(characterId, characterInfo)
    -- Store the name per-realm since it might be possible to have the same names on different realms.
    self.totals[characterInfo.realm]._formattedCharacterNames[characterInfo.name] =
      BsCharacter:FormatCharacterName(characterId)
  end

  -- Reusable tables for storing tooltip data.
  local addTooltipInfo_LeftStrings = {}
  local addTooltipInfo_RightStrings = {}

  --- Add counts for the given itemString to the provided tooltip.
  ---@param itemString string Item to gather counts for.
  ---@param tooltip table WoW GameTooltip object.
  ---@return boolean linesAdded true if one or more lines were added to the tooltip.
  function Catalog:AddTooltipInfo(itemString, tooltip)
    assert(
      type(tooltip) == "table" and tooltip.AddDoubleLine,
      "Catalog:AddTooltipInfo() - tooltip must be a WoW GameTooltip object"
    )

    -- Can't add any data until the class is up and running.
    if not self.initialized then
      return false
    end

    BsUtil.TableClear(addTooltipInfo_LeftStrings)
    BsUtil.TableClear(addTooltipInfo_RightStrings)

    -- When characters from more than one realm have the item, we'll want to add a grand total line.
    local realmsWithItems = 0

    -- Current realm always goes at the top.
    if self:GetPerRealmTooltipInfo(itemString, Bagshui.currentRealm) > 0 then
      realmsWithItems = realmsWithItems + 1
    end

    -- Now add all the other realms.
    for _, realm in ipairs(self.sortedRealmList) do
      if realm ~= Bagshui.currentRealm then
        if self:GetPerRealmTooltipInfo(itemString, realm) > 0 then
          realmsWithItems = realmsWithItems + 1
        end
      end
    end

    -- Populate the tooltip.
    if table.getn(addTooltipInfo_LeftStrings) > 0 then
      if tooltip:NumLines() > 0 then
        tooltip:AddLine(" ")
      end

      -- Grand total for multi-realm.
      if realmsWithItems > 1 then
        tooltip:AddDoubleLine(
          HIGHLIGHT_FONT_COLOR_CODE .. L.Total .. FONT_COLOR_CODE_CLOSE,
          HIGHLIGHT_FONT_COLOR_CODE .. self:GetTotal(self.totals, nil, itemString) .. FONT_COLOR_CODE_CLOSE
        )
      end

      -- Add tooltip lines, indenting the left side in multi-realm mode.
      for lineNum, left in ipairs(addTooltipInfo_LeftStrings) do
        tooltip:AddDoubleLine(
          (realmsWithItems > 1 and TOOLTIP_INDENT or HIGHLIGHT_FONT_COLOR_CODE) .. left .. FONT_COLOR_CODE_CLOSE,
          addTooltipInfo_RightStrings[lineNum]
        )
      end

      return true
    else
      tooltip:AddDoubleLine(
        GRAY_FONT_COLOR_CODE .. L.Total .. FONT_COLOR_CODE_CLOSE,
        GRAY_FONT_COLOR_CODE .. 0 .. FONT_COLOR_CODE_CLOSE
      )
    end

    return false
  end

  --- When at least 1 of the given item is held by one or more characters on the specified realm,
  --- add all the tooltip data for that realm to the reusable strings tables.
  ---@param itemString string Item to gather counts for.
  ---@param realm string Realm to get counts for.
  ---@return integer realmCount Total count of the given item found on the specified realm.
  function Catalog:GetPerRealmTooltipInfo(itemString, realm)
    -- This realm has no data.
    if not self.totals[realm] then
      return 0
    end

    local overallTotal = self:GetTotal(self.totals[realm], nil, itemString)

    if (overallTotal or 0) > 0 or itemString == BS_CATALOG_LOCATIONS.MONEY then
      -- Realm-wide total goes first.
      self:AddTooltipInfoLine(
        realm,
        HIGHLIGHT_FONT_COLOR_CODE
          .. (itemString == BS_CATALOG_LOCATIONS.MONEY and BsUtil.FormatMoneyString(overallTotal) or overallTotal)
          .. FONT_COLOR_CODE_CLOSE
      )

      -- Add the total held by each character (if more than 0)
      local characterTotals
      for _, characterName in ipairs(self.totals[realm]._sortedCharacterList) do
        characterTotals = self.totals[realm][self:TotalKey(characterName)][itemString]
        if characterTotals then
          self:AddTooltipInfoLine(
            TOOLTIP_INDENT .. self.totals[realm]._formattedCharacterNames[characterName],
            characterTotals
          )
        end
      end
    end

    return overallTotal
  end

  --- Add the given strings to the reusable tooltip storage tables, to be consumed
  --- by `AddTooltipInfo()`.
  ---@param left string?
  ---@param right string?
  function Catalog:AddTooltipInfoLine(left, right)
    table.insert(addTooltipInfo_LeftStrings, left or "")
    table.insert(addTooltipInfo_RightStrings, right or "")
  end

  --- Get an item from the catalog by matching name and (optionally) texture.
  --- Useful when item ID isn't known (like for some hooked tooltip functions).
  --- This doesn't guarantee a 100% match since there are a few items that have
  --- the same name and texture but different IDs (Recruit's Boots/Pants/Shirt).
  ---@param name string Item name.
  ---@param texture string? Item texture (recommended for a guaranteed accurate match).
  ---@param property string? Extract a single item property instead of returning the entire item table.
  ---@return table|string? # Item table or item property.
  function Catalog:FindItemByNameAndTexture(name, texture, property)
    for _, item in ipairs(self.items) do
      if item.name == name and (not texture or item.texture == texture) then
        if property then
          return item[property]
        else
          return item
        end
        break
      end
    end
  end

  --- Build the account-wide search interface.
  function Catalog:InitUi()
    -- Don't initialize multiple times.
    if self.objectManager then
      return
    end

    -- Upvalue for use inside ObjectManager class functions.
    local catalog = self

    self.objectManager = Bagshui.prototypes.ObjectManager:New({
      objectType = "Catalog",
      listType = BS_UI_SCROLLABLE_LIST_TYPE.ITEM,
      managerMultiSelect = false,
      disableObjectCreation = true,
      disableObjectDeletion = true,
      disableObjectEditing = true,
      disableObjectSharing = true,
      managerHeight = 700,
      managerWidth = 400,
      searchPlaceholderText = L.CatalogManager_SearchBoxPlaceholder,
      wikiPage = BS_WIKI_PAGES.Search,
    })

    function self.objectManager:InitUi()
      self._super.InitUi(self)
      self.ui.searchBox:SetWidth(self.dimensions.width * 0.6)

      -- Add CharacterData manager button to toolbar.
      local characterButton = self.ui:CreateIconButton({
        name = "Character",
        texture = "CharacterRobed",
        parentFrame = self.toolbar,
        anchorPoint = "RIGHT",
        anchorToPoint = "RIGHT",
        xOffset = -2,
        noTooltipDelay = true,
        noTooltipTextDelay = true,
        tooltipAnchor = "ANCHOR_PRESERVE",
        tooltipAnchorPoint = "TOPRIGHT",
        tooltipAnchorToPoint = "BOTTOMRIGHT",
        tooltipXOffset = 4,
        tooltipYOffset = -4,
        tooltipFunction = function(button, tooltip)
          tooltip:AddLine(
            HIGHLIGHT_FONT_COLOR_CODE .. string.format(L.Prefix_Manage, L.CharacterData) .. FONT_COLOR_CODE_CLOSE
          )
          tooltip:AddLine(BS_NEWLINE .. L.CatalogManager_KnownCharacters)
          tooltip:AddLine("- " .. table.concat(BsCharacterData.characterNameList, BS_NEWLINE .. "- "))
        end,
        onClick = function()
          BsCharacterData:Open()
        end,
      })
    end

    function self.objectManager:GetObjectList()
      return catalog.items
    end
  end

  --- Open the account-wide search interface, optionally with a pre-populated search string.
  ---@param searchString string? Search string to pre-populate.
  function Catalog:Open(searchString)
    self:Init()
    self:InitUi()
    self.objectManager.Open(self.objectManager)
    if type(searchString) == "string" then
      self.objectManager.ui.listFrame.bagshuiData.searchBox:SetText(searchString)
    end
  end

  --- Hide the catalog window.
  function Catalog:Close()
    self.objectManager:Close()
  end

  --- Open the Catalog if it's closed and vice-versa.
  function Catalog:Toggle()
    if self:Visible() then
      self.objectManager:Close()
    else
      self:Open()
    end
  end

  --- Determine whether the Catalog window is open.
  function Catalog:Visible()
    return self.objectManager and self.objectManager.uiFrame and self.objectManager.uiFrame:IsVisible()
  end

  --- Open and search the Catalog, setting focus on the search box.
  ---@param searchString string? Search string to pre-populate.
  function Catalog:Search(searchString)
    self:Open(searchString)
    self.objectManager.ui.listFrame.bagshuiData.searchBox:SetFocus()
  end

  -- Class event registration.
  -- This is done at the end because RegisterEvent expects the class to have an OnEvent function.
  Bagshui:RegisterEvent("PLAYER_ENTERING_WORLD", Catalog)
  Bagshui:RegisterEvent("BAGSHUI_CHARACTER_UPDATE", Catalog)
  Bagshui:RegisterEvent("BAGSHUI_CHARACTER_LEARNED_RECIPE", Catalog)
  Bagshui:RegisterEvent("BAGSHUI_EQUIPPED_UPDATE", Catalog)
  Bagshui:RegisterEvent("BAGSHUI_INVENTORY_CACHE_UPDATE", Catalog)
  Bagshui:RegisterEvent("BAGSHUI_MONEY_UPDATE", Catalog)
  Bagshui:RegisterEvent("BAGSHUI_CATALOG_SHOULD_UPDATE", Catalog)
end)

