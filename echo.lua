local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"

local http_method = ngx.req.get_method()
ngx.say("method: ", http_method)

local headers = ngx.req.get_headers()
for k,v in pairs(headers) do
	ngx.say(k, " : ", v)
end

local args = ngx.req.get_uri_args()
for k,v in pairs(args) do
	ngx.say(k, " : ", v)
end

ngx.say("I_am_alive")

