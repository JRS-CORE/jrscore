Config = {}

-- GitHub repository that hosts JRS Core ("owner/name") and the branch to compare against.
Config.Repo   = 'JRS-CORE/jrscore'
Config.Branch = 'main'

-- Only resources whose name starts with one of these prefixes are compared.
-- Add resource names to Config.Include to track resources that do not use a prefix.
Config.Prefixes = { 'jrs_' }
Config.Include  = { 'bee_house' }

-- Check when the server starts (after StartDelaySec) and then every IntervalHours.
-- Set IntervalHours = 0 to check only at start.
Config.CheckOnStart  = true
Config.StartDelaySec = 30
Config.IntervalHours = 6

-- Parallel raw.githubusercontent.com requests.
Config.Concurrency = 6

-- Show resources that exist on GitHub but are not installed on this server.
Config.ShowNewResources = true

-- Optional Discord webhook, set it in server.cfg instead of here:
--   set jrs_updater_webhook "https://discord.com/api/webhooks/..."
Config.WebhookConvar = 'jrs_updater_webhook'

-- Console command to run a check manually (console / ACE only).
Config.Command = 'jrs_updater'
