local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local shell = require "resty/shell"
local string = require "resty/string"

local mutex_dict = ngx.shared.mutex_dict

local args = ngx.req.get_uri_args()
local domain_name = args["domain_name"]
local file_name = args["file_name"] 
local file_date = args["file_date"]
local request = args["request"]
if not domain_name or not file_name or not file_date or not request then
	ngx.log(ngx.ERR, "no domain_name or file_name, ", domain_name, ", ", file_name,
					", ", file_date, ", ", request)
	ngx.exit(ngx.HTTP_ILLEGAL)
end

local lock_file_key = "hadoop"..domain_name..file_name

if request == "lock" then
	--30s应该够了
	local ok, err, forcible = mutex_dict:add(lock_file_key, 1, 30)
	if ok then
		ngx.log(ngx.DEBUG, "got mutex for: ", lock_file_key, ", forcible: ", forcible)
		ngx.say("yes_to_send")
	else
		ngx.log(ngx.WARN, "get mutex failed, err: ", err)
		ngx.say("wait_a_while")
	end	

	ngx.exit(ngx.HTTP_OK)
end

if request == "unlock" then
	ngx.log(ngx.DEBUG, "release mutex for: ", lock_file_key)
	mutex_dict:delete(lock_file_key)
	ngx.exit(ngx.HTTP_OK)
end

ngx.say("wrong_request")
ngx.exit(ngx.HTTP_OK)
