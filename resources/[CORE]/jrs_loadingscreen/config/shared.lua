-- ==========================================================================
--  JRS CORE  |  jrs_loadingscreen  |  config/shared.lua
--  JRS Loading Screen - RedM / jrs_core compatible
-- ==========================================================================

Config = Config or {}

Config.Debug = false

Config.JRS = {
    coreResource = 'jrs_core',
    characterResource = 'jrs_character',

    -- Primary handoff: jrs_character fires this only after the Character Selector
    -- or Character Creator NUI confirms that it has actually been painted.
    characterCloseEvent = 'jrs_loadingscreen:client:close',
    characterSelectionReadyEvent = 'jrs_loadingscreen:client:characterSelectionReady',
    characterDismissedEvent = 'jrs_character:client:loadingDismissed',
    characterSkipShowEvent = 'jrs_character:client:loadingSkipAvailable',
    characterCursorClaimEvent = 'jrs_character:client:claimSelectorCursor',

    -- Legacy / emergency signals kept only as compatibility fallbacks.
    coreReadyEvent = 'jrs_core:client:characterReady',
    selectedCharacterEvent = 'jrs:SelectedCharacter',
    finalReadyEvent = 'jrs_character:isPlayerReady',
    legacyReadyEvent = 'jrs:isPlayerReady',
    legacyReadyEventLower = 'jrs:isPlayerready',

    -- If jrs_character is not running, preserve the old standalone behavior.
    closeAfterInitialSpawnMs = 450,
    standaloneWatchdogMs = 30000,

    -- When jrs_character is running we intentionally wait for its explicit UI-ready
    -- event. This long watchdog is only a last-resort recovery for a broken creator.
    characterUiFallbackMs = 240000,

    readyBackupDelayMs = 100,
    manualCloseDelayMs = 100,
}


-- Character selector handoff. The selector can finish rendering behind the
-- loading screen, then expose a SKIP button. If the player does nothing the
-- loading screen is dismissed automatically after the configured duration.
Config.CharacterSkip = {
    -- Keep false for the normal JRS flow: selector-ready immediately closes
    -- the manual loading screen, then jrs_character takes exclusive mouse focus.
    -- Set true only if you intentionally want the legacy 60-second SKIP overlay.
    holdAfterSelectorReady = false,
    enabled = true,
    buttonText = _U('skip_button'),
    autoCloseSeconds = 60,
}

Config.Dev = {
    enabled = false,
    forceCloseCommand = 'jrs_loading_close',
}
