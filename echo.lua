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

ngx.req.read_body()
local data = ngx.req.get_body_data()

if not data then
	data = util.read_file_data(ngx.req.get_body_file())
end

ngx.say("body: ", data)


