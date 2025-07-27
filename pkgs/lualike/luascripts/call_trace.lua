---
--- Created by kingwill101.
--- DateTime: 3/2/25 8:14 AM
---
  require("tracegc").start()
        local propResult = require("tracegc").property("status")
        local status = require("tracegc").status
        print("status", status)
        print("propResult", propResult)