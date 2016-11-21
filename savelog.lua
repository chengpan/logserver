local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local shell = require("resty.shell")

local http_method = ngx.req.get_method()
if http_method ~= "POST" then
	ngx.log(ngx.ERR, "not post method: ", http_method)
	ngx.exit(ngx.HTTP_ILLEGAL)
end

local content_length = tonumber(ngx.req.get_headers()["Content-Length"])
if not content_length then
	ngx.log(ngx.ERR, "no content_length ", ngx.req.get_headers()["Content-Length"])
	ngx.exit(ngx.HTTP_ILLEGAL)
end

if content_length < 5 then
	ngx.log(ngx.ERR, "ignore, post data too short!!! : ", content_length)
	ngx.say("upload_success")
	ngx.exit(ngx.HTTP_OK)
end

local args = ngx.req.get_uri_args()
local query_file = args["file"]
if query_file then
	--这是错误的,后续使用domain_name 和file_name
	--ngx.log(ngx.ERR, "this should not happen") 
	ngx.say("upload_success")
	ngx.exit(ngx.HTTP_OK)
end

local domain_name = args["domain_name"]
local file_name = args["file_name"] --这个file_name已经去掉分钟部分了
local file_date = args["file_date"]
if not domain_name or not file_name or not file_date then
	ngx.log(ngx.ERR, "no domain_name or file_name, ", domain_name, ", ", file_name,
					", ", file_date)
	ngx.exit(ngx.HTTP_ILLEGAL)
end

ngx.log(ngx.DEBUG, "domain_name: ", domain_name,
					", file_name: ", file_name,
					", file_date: ", file_date,
					", remote_addr: ", ngx.var.remote_addr,
					", X-Real-IP: ", ngx.var["X-Real-IP"])

--读取数据
ngx.req.read_body()
local data = ngx.req.get_body_data()
local tmp_body_file = ngx.req.get_body_file()
if not tmp_body_file then
	ngx.log(ngx.ERR, "no body file")
	ngx.exit(ngx.HTTP_ILLEGAL)
end

--[[
if not data then
	data = util.read_file_data(ngx.req.get_body_file())
end

--如果数据不存在或者长度不对,不接受
if not data or #data ~= content_length then
	ngx.log(ngx.ERR, "no post data or data length wrong: ", #data, ", Content-Length: ", content_length)
	ngx.exit(ngx.HTTP_ILLEGAL)
end
--]]

--分析文件,确定下载目录和保存日志的文件路径
--保存路径 log_dir + 日期 + domain + 单个小时的文件 
--比如 /data2/log_process/download/20161019/www.ucloud.cn/http_access.20161017.log.1  
local store_dir = conf.log_file_dir
local file_dir  = store_dir..file_date.."/"..domain_name.."/"
local file_path = file_dir..file_name

local lock_file_key = domain_name..file_name

ngx.log(ngx.DEBUG, "appending to ", file_path)

--[=[
--O_APPEND打开文件,路径文件夹不存在就创建
local log_file_handle, err = io.open(file_path, "a")
if not log_file_handle then
	ngx.log(ngx.ERR, "open log_file failed: ", err, ", try to create dir ", file_dir)
	local retcode = os.execute("mkdir -p "..file_dir)
	ngx.log(ngx.DEBUG, "os retcode: ", retcode)
end

log_file_handle, err = io.open(file_path, "a")
if not log_file_handle then
	ngx.log(ngx.ERR, "still failed: ", err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

--get mutex
local lock_file_status = util.get_mutex_lock(lock_file_key)
if not lock_file_status then
	ngx.log(ngx.ERR, "can't lock file to write data")
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

--写入文件后关闭文件
log_file_handle:write(data)
log_file_handle:close()

--release mutex
util.release_mutex_lock(lock_file_key)

--]=]

--get mutex
--[[
local lock_file_status = util.get_mutex_lock(lock_file_key)
if not lock_file_status then
	ngx.log(ngx.ERR, "can't lock file to write data")
	--ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end
--]]


--[[
local args = {socket = "unix:/tmp/shell.sock"}

local cmd = string.format("cat %s >> %s", tmp_body_file, file_path)
local status, out, err = shell.execute(cmd, args)
if status ~= 0 then
	ngx.log(ngx.ERR, "status: ", status, ", out: ", out, ", err: ", err)
	local index = string.find(err, "No such file or directory")
	if not index then
		ngx.log(ngx.DEBUG, "not caused by directory")
		ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
	end

	ngx.log(ngx.ERR, "need to create directory")
	status, out, err = shell.execute("mkdir -p "..file_dir, args)
	if status ~= 0 then
		ngx.log(ngx.ERR, "status: ", status, ", out: ", out, ", err: ", err)
		--util.release_mutex_lock(lock_file_key)
		ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
	end

	status, out, err = shell.execute(cmd, args)
	if status ~= 0 then
		ngx.log(ngx.ERR, "status: ", status, ", out: ", out, ", err: ", err)
		--util.release_mutex_lock(lock_file_key)
		ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)		
	end
end
--]]

---[[
local status, msg = util.file_copy(tmp_body_file, file_path)
if status ~= 0 then
	ngx.log(ngx.ERR, "status: ", status, ", msg: ", msg)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end
--]]

--[[
--写入文件
--使用文件cache
local filecache = require("resty.filecache")
local err = filecache.write(file_path, data)
if err then 
    ngx.log(ngx.ERR, "write log to [", file_path, "] failed! err:", tostring(err))
    util.release_mutex_lock(lock_file_key)
    ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end
--]]
--release mutex
--util.release_mutex_lock(lock_file_key)


--返回成功信息
ngx.say("upload_success")
ngx.exit(ngx.HTTP_OK)
