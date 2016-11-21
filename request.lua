local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"

local uri_args = ngx.req.get_uri_args()
for k, v in pairs(uri_args)
do
	ngx.say(k, " : ", v)
end

ngx.sleep(3);

local db, err = mysql:new()
if not db then
	ngx.say("failed to instantiate mysql: ", err)
	return
end

db:set_timeout(1000) -- 1 sec

local ok, err, errcode, sqlstate = db:connect(conf.domain_ip_db)

if not ok then
	ngx.say("failed to connect: ", err, ": ", errcode, " ", sqlstate)
	return
end

ngx.say("connected to mysql.")

local res, err, errcode, sqlstate = db:query("select * from tb_domain_conf limit 2")
if not res then
	ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
	return
end

ngx.say("2 result: \r\n", json.encode(res))

local ok, err = db:set_keepalive(10000, 100)
if not ok then
	ngx.say("failed to set keepalive: ", err)
	return
end

ngx.exit(ngx.HTTP_OK)
