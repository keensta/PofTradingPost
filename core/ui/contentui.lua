local TradingPostUI = require("core/ui/tradingpost")

local ContentUI = {
    view = nil
}
local SUBSCRIBER_ID = "pofTradingPost_contentUI"

function ContentUI.init()
    Event.ContentLayerReady.Subscribe(SUBSCRIBER_ID, function(event)

        if ContentUI.view then
            ContentUI.view:Destroy()
        end

        local parent = event.component

        ContentUI.view = prettyui.SimpleView.new(parent, {
            categoryID = "auto",
            width = parent.width,
            height = parent.height
        })

        ContentUI.view:AddTitle("POF Trading Post")
        ContentUI.view:AddSimpleButton("Open Trading Post", function()
            TradingPostUI.toggle()
        end)
    end)
end


function ContentUI.shutdown()
    Event.ContentLayerReady.Unsubscribe(SUBSCRIBER_ID)

    if ContentUI.view then
        pcall(function()
            ContentUI.view:Destroy()
        end)

        ContentUI.view = nil
    end
end

return ContentUI
