local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local shell = require "resty/shell"
local resty_string = require "resty/string"

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
	--300s应该够了
	local ok, err, forcible = mutex_dict:add(lock_file_key, 1, 300)
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

	--只提供分片下载
--[[
	--之前的打包文件必须删除了
	local gz_log_path = conf.gzip_log_dir..file_date.."/"..domain_name.."/"..file_name..".gz"
	local cmd = string.format("[ -f %s ] && rm -f %s", gz_log_path, gz_log_path)
	ngx.log(ngx.DEBUG, "cmd: ", cmd)

	local args = {socket = "unix:/tmp/shell.sock", timeout = 5000}
	local status, out, err = shell.execute(cmd, args)
	ngx.log(ngx.DEBUG, "cmd: ", cmd, "status: ", status, ", out: ", out, ", err: ", err)
	if status ~= 0 and status ~= 256 then
		ngx.log(ngx.ERR, "cmd: ", cmd, "status: ", status, ", out: ", out, ", err: ", err)
	end	
--]]	
	ngx.exit(ngx.HTTP_OK)
end

ngx.say("wrong_request")
ngx.exit(ngx.HTTP_OK)
