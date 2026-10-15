-- ==========================================================================
--  JRS CORE  |  jrs_billing  |  config.lua
--  job billing: /bill a nearby player, money to the biller, receipt item
-- ==========================================================================

BillingConfig = {}

BillingConfig.Command = "bill"          -- /bill opens the billing form
BillingConfig.MaxBillAmount = 1000      -- highest amount one bill can have
BillingConfig.MaxDistance = 5.0         -- the billed player must be this close (meters)
BillingConfig.GiveMoneyToBiller = true  -- the paid money goes to the player who wrote the bill
BillingConfig.GiveReceipt = true        -- the billed player gets a receipt item
BillingConfig.ReceiptItem = "receipt"
BillingConfig.ServerYear = 1899         -- year printed on the receipt

-- Jobs allowed to bill and their minimum grade.
-- Off-duty jobs in JRS have their own names (offvalsheriff...), so being in
-- one of these jobs already means "on duty".
BillingConfig.Jobs = {
    police = 0,
    valsheriff = 0,
    bwsheriff = 0,
    armsheriff = 0,
    twsheriff = 0,
    stbsheriff = 0,
    doctor = 0,
    Medic = 0,
}

-- Discord webhook for bill logs ("" = off)
BillingConfig.Webhook = ""
