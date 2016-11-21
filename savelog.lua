local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local shell = require "resty/shell"
local string = require "resty/string"

local http_method = ngx.req.get_method()
if http_method ~= "POST" then
	ngx.log(ngx.ERR, "not post method: ", http_method)
	ngx.exit(ngx.HTTP_ILLEGAL)
end

local content_length = tonumber(ngx.req.get_headers()["Content-Length"])
ngx.log(ngx.DEBUG, "content_length: ", content_length)
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
local tmp_body_file = ngx.req.get_body_file()
if not tmp_body_file then
	ngx.log(ngx.ERR, "no body file")
	ngx.exit(ngx.HTTP_ILLEGAL)
end

--分析文件,确定下载目录和保存日志的文件路径
--保存路径 log_dir + 日期 + domain + 单个小时的文件 
--比如 /data2/log_process/download/20161019/www.ucloud.cn/http_access.20161017.log.1  
local store_dir = util.get_log_dir(domain_name)
local file_dir  = store_dir..file_date.."/"..domain_name.."/"
local file_path = file_dir..file_name

local lock_file_key = domain_name..file_name

ngx.log(ngx.DEBUG, "appending to ", file_path)


--get mutex
local lock_file_status = util.get_mutex_lock(lock_file_key)
if not lock_file_status then
    ngx.log(ngx.ERR, "can't lock file to write data")
    ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local status, msg = util.file_copy(tmp_body_file, file_path)
if status ~= 0 then
	ngx.log(ngx.ERR, "status: ", status, ", msg: ", msg)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local m, err = ngx.re.match(msg, "[0-9]+", "o")
if not m then
	ngx.log(ngx.ERR, "regex error: ", err)
end

local bytes = tonumber(m[0])
ngx.log(ngx.DEBUG, bytes, " bytes copied!")
if bytes ~= content_length then
	ngx.log(ngx.ERR, "wrong! ", bytes, " != ", content_length)
end

--release mutex
util.release_mutex_lock(lock_file_key)

--返回成功信息
ngx.say("upload_success")
ngx.exit(ngx.HTTP_OK)
