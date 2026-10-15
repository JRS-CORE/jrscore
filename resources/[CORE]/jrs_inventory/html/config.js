var config = {}
config.debug = false // JavaScript console logs (Dev Mode)

// Inventory interface sounds
config.uiSounds = {
    enabled: true,
    clickEnabled: true,
    openEnabled: true,
    closeEnabled: true,
    clickVolume: 0.34,
    openVolume: 0.40,
    closeVolume: 0.38,
    clickCooldownMs: 45
}
config.language = [
    {text:"Items"},
    {text:"Weapons"},
    {text:"Storage"},
    {text:"Slots"},
    {text:"Outfit manage"},
    {text:"Wear or unwear hat"},
    {text:"Wear or unwear glass"},
    {text:"Wear or unwear mask"},
    {text:"Wear or unwear bandana"},
    {text:"Wear or unwear scarf"},
    {text:"Wear or unwear cloak or poncho"},
    {text:"Wear or unwear shirt"},
    {text:"Wear or unwear vest"},
    {text:"Wear or unwear coat"},
    {text:"Wear or unwear ammo, accesories, backs"},
    {text:"Wear or unwear rings"},
    {text:"Wear or unwear gloves"},
    {text:"Wear or unwear gauntlets"},
    {text:"Wear or unwear belt, holster etc."},
    {text:"Wear or unwear suspenders"},
    {text:"Wear or unwear chaps, pants"},
    {text:"Wear or unwear boots"},
    {text:"Money"},
    {text:"Currency for pay."},
    {text:"Gold"},
    {text:"Currency for pay."},
    {text:"Equiped"},
    {text:"Unequiped"},
    {text:"Close"},
    {text:"Inventory"},
    {text:"Give"},
    {text:"Drop"},
    {text:"Loading..."},
    {text:"Dirty Money"},
    {text:"Illegal / dirty currency."},
]

// The entries above are the English fallback (used before the real language
// arrives, and if a JrsI18n pack is ever missing a key). Once jrs-i18n.js has
// the player's language, only the indices something in index.js actually
// reads get overwritten - the rest of the array is unused dead weight from
// before jrs-i18n.js existed.
function applyConfigLanguage() {
    if (typeof JrsI18n === 'undefined') return
    config.language[0].text = JrsI18n.t('inv_cfg_items', config.language[0].text)
    config.language[1].text = JrsI18n.t('inv_weapons', config.language[1].text)
    config.language[2].text = JrsI18n.t('inv_storage_2', config.language[2].text)
    config.language[22].text = JrsI18n.t('inv_money', config.language[22].text)
    config.language[23].text = JrsI18n.t('inv_currency_for_pay', config.language[23].text)
    config.language[24].text = JrsI18n.t('inv_gold', config.language[24].text)
    config.language[25].text = JrsI18n.t('inv_currency_for_pay', config.language[25].text)
    config.language[26].text = JrsI18n.t('inv_equipped', config.language[26].text)
    config.language[27].text = JrsI18n.t('inv_unequipped', config.language[27].text)
    config.language[28].text = JrsI18n.t('inv_close', config.language[28].text)
    config.language[29].text = JrsI18n.t('inv_inventory', config.language[29].text)
    config.language[33].text = JrsI18n.t('inv_dirty_money', config.language[33].text)
    config.language[34].text = JrsI18n.t('inv_illegal_dirty_currency', config.language[34].text)
}
if (typeof JrsI18n !== 'undefined') {
    JrsI18n.onChange(applyConfigLanguage)
    applyConfigLanguage()
}
