-- jrs_metabolism | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
--[[
Consumable Functions 

    Coffee()
    Shampan()
    Drink()
    Eat()
    Beer()
    Whisky()
    Moonshine()
    Wine()

]]



ConsumableItems = {
    -- //////////////////////////////-- Drink --//////////////////////////////////////////////
   ["water"] = {
       hunger = 0,
       thirst = 50,
       ClientAction = function()
           Drink()
         -- addStaminaFromPed(PlayerPedId(), 4)
       end
   },
   ["consumable_coffee"] = {
       hunger = 0,
       thirst = 20,
       ClientAction = function()
           Drink()
       end
   },
   ["milk"] = {
       hunger = 0,
       thirst = 40,
       ClientAction = function()
        Drink()
           -- Drink()
       end
   },
   ["potionreanimation"] = {
       hunger = 0,
       thirst = 60,
       ClientAction = function()
           Drink()
       end
   },
   ["potionsoin"] = {
       hunger = 0,
       thirst = 45,
       ClientAction = function()
           Drink()
       end
   },
   ["potiontransformation"] = {
       hunger = 0,
       thirst = 50,
       ClientAction = function()
           Drink()
       end
   },
   ["raspberryale"] = {
       hunger = 0,
       thirst = 30,
       ClientAction = function()
           Drink()
       end
   },
   ["tequila"] = {
       hunger = 0,
       thirst = 30,
       ClientAction = function()
           Drink()
       end
   },
   ["consumable_raspberrywater"] = {
       hunger = 0,
       thirst = 30,
       ClientAction = function()
           Drink()
       end
   },
  
   -- //////////////////////////////-- wine -- ///////////////////////////////////////

   ["beer"] = {
       hunger = -1,
       thirst = 10,
       ClientAction = function()
           Wine()
       end
   },
   ["whisky"] = {
       hunger = -10,
       thirst = 10,
       ClientAction = function()
           Wine()
       end
   },
   ["shampan"] = {
       hunger = 0,
       thirst = 0,
       ClientAction = function()
           Wine()
       end
   },

-- //////////////////////////////-- eat --//////////////////////////////////////////////
   ["grapes"] = {
       hunger = 40,
       thirst = 10,
       ClientAction = function()
           Eat()
       end
   },
   ["volaille"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["volaillerotie"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["poisson"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["poissongrille"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["viandepetitgibier"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["petitgibiergrille"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["viandegibier"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["gibiergrille"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["viandegrosgibier"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["grosgibiergrille"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["tomato"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["banana"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["coconut"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["kiwi"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["lemon"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["mango"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["melon"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["pineapple"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["orangees"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["carrot"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["lettuce"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["potato"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["raisin"] = {
       hunger = 40,
       thirst = 10,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_kidneybeans_can"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_salmon_can"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["blueberry"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["cookedbluegil"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_peach"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_blueberrypie"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["steak"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_breakfast"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["honey"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["kidneybeans"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_bluegil"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["Blueberries"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_caramel"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["bread"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["cookedsmallgame"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_chocolate"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_fruitsalad"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_game"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_herb_chanterelles"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_herb_evergreen_huckleberry"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_herb_oregano"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_herb_vanilla_flower"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_herb_wintergreen_berry"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_meat_greavy"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_salmon"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_veggies"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_pear"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["steakveg"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["porkcooked"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["knifecooking"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_applepie"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["SaltedCookedBigGameMeat"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["CookedBigGameMeat"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["cookedpork"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["cookedbird"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["plainsmallgame"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["steakeggs"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["vegstew"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["porknapples"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["birdstew"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["ceai_menta"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["consumable_medicine"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["wojape"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["pomme"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["betterave"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["haricot"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
    ["ragout"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
   ["soupepoisson"] = {
       hunger = 50,
       thirst = 0,
       ClientAction = function()
           Eat()
       end
   },
}