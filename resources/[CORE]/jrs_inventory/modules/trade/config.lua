-- ==========================================================================
--  JRS CORE  |  jrs_inventory  |  modules/trade/config.lua
--  JRS Inventory unified resource: inventory + weapons + storage + ground + robbery + transactional trade
-- ==========================================================================

TradeConfig = {}

TradeConfig.Command = 'trade'
TradeConfig.ReopenCommand = 'tradeopen'
TradeConfig.MaxDistance = 5.0
TradeConfig.RequireNearbyToPay = true
TradeConfig.InviteSeconds = 30
TradeConfig.OfferExpireMinutes = 30
TradeConfig.MinPrice = 1
TradeConfig.MaxPrice = 10000000
TradeConfig.MaxItemLines = 30
TradeConfig.MaxWeaponLines = 10
TradeConfig.Debug = false

-- Item / weapon icons are reused from jrs_inventory. Relative path works in all NUI protocols.
TradeConfig.InventoryImageBase = '../../images/items/'

TradeConfig.Text = {
    title = 'SECURE TRADE',
    invalidTarget = 'Invalid player ID.',
    targetTooFar = 'The player is too far away.',
    busy = 'One of the players already has an active trade.',
    invited = 'Trade request sent.',
    inviteReceived = 'You received a trade request.',
    inviteExpired = 'Trade request expired.',
    declined = 'Trade request declined.',
    noTrade = 'You do not have an active trade.',
    sellerOnly = 'Only the seller can edit this offer.',
    locked = 'Offer locked. The items are now held in escrow.',
    cancelled = 'Trade cancelled.',
    insufficientMoney = 'You do not have enough money.',
    buyerFull = 'Your inventory does not have enough capacity.',
    buyerWeaponFull = 'You cannot carry all weapons in this trade.',
    sellerOffline = 'The seller must be online to finish payment.',
    completed = 'Trade completed successfully.',
    failed = 'Trade operation failed.',
    weaponEquipped = 'Unequip the weapon before adding it to the trade.',
    activeRestored = 'You have an active locked trade. Use /tradeopen to reopen it.',
    select_nearby = 'Select a valid nearby player.',
    use_command = 'Use /%s [player ID]',
}
