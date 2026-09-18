-- Save this package as a local Studio plugin. Runtime game scripts do nothing.
if not plugin then return end

local root = script.Parent
local Widget = require(root.UI.MonitorWidget)
local Controller = require(root.UI.MonitorController)
local view = Widget.new(plugin)
local monitor = Controller.new(view, game)

plugin.Unloading:Connect(function() monitor:Destroy() end)
monitor:Start()
