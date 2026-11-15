local App = require("core/app")

--print("POF Trading Post Booting Up...")
App.start()


function PluginShutdown()
    App.shutdown()
end