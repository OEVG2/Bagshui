-- Bagshui UI Skinning settings processing.
-- Exposes: BsSkin (and Bagshui.components.Skin)
--
-- Skin tables are defined in Config\Skins.lua, which also picks the automatic default
-- (pfUI when it is skinning Bagshui, otherwise Classic). All we're doing here is:
-- 1. Pointing the BsSkin Bagshui environment variable to the active skin.
-- 2. If the active skin isn't the original, applying a metatable so that anything
--    missing from the active skin will be picked up from the original.
-- 3. Once SavedVariables are available, honoring the user's "theme" setting.

Bagshui:LoadComponent(function()
  local Skins = Bagshui.config.Skins

  --- Make the named skin active.
  ---@param skinName string Key of Bagshui.config.Skins.
  local function applySkin(skinName)
    local skin = Skins[skinName]
    if type(skin) ~= "table" then
      skinName = "Bagshui"
      skin = Skins.Bagshui
    end
    if skinName ~= "Bagshui" then
      setmetatable(skin, Skins.Bagshui)
      Skins.Bagshui.__index = Skins.Bagshui
    end
    Skins.activeSkin = skinName
    Bagshui.environment.BsSkin = skin
    Bagshui.components.Skin = skin
  end

  -- Automatic choice, available immediately.
  applySkin(Skins.activeSkin)

  -- Components queued with AddComponent() run after SavedVariables are loaded,
  -- so that's where the user's theme choice can be applied.
  Bagshui:AddComponent(function()
    local theme = _G.BagshuiData and _G.BagshuiData.settings and _G.BagshuiData.settings.theme
    local choice
    if theme == "original" then
      choice = "Bagshui"
    elseif theme == "classic" then
      choice = "Classic"
    elseif theme == "pfui" then
      -- Falls back to Classic when pfUI isn't skinning Bagshui.
      choice = Skins.pfUI and "pfUI" or "Classic"
    end
    if choice and choice ~= Skins.activeSkin then
      applySkin(choice)
    end
  end)
end)
