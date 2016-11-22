local util  = require "comm/util"
local webhdfs  = require "comm/webhdfs"

--[[
ngx.log(ngx.DEBUG, "test lua file at: ", ngx.localtime())
ngx.log(ngx.DEBUG, "test lua file at: ", util.get_datetime())

ngx.say("http_user_agent: ", ngx.var.http_user_agent)
ngx.say("http_cookie: ", ngx.var.http_cookie)
ngx.say("args: ", ngx.var.args)
ngx.say("content_length: ", ngx.var.content_length)
ngx.say("content_type: ", ngx.var.content_type)
ngx.say("document_root: ", ngx.var.document_root)
ngx.say("document_uri: ", ngx.var.document_uri)
ngx.say("host: ", ngx.var.host)
ngx.say("limit_rate: ", ngx.var.limit_rate)
ngx.say("request_method: ", ngx.var.request_method)
ngx.say("remote_addr: ", ngx.var.remote_addr)
ngx.say("X-Real-IP: ", ngx.var["X-Real-IP"])
ngx.say("remote_port: ", ngx.var.remote_port)
ngx.say("remote_user: ", ngx.var.remote_user)
ngx.say("request_body_file: ", ngx.var.request_body_file)
ngx.say("request_uri: ", ngx.var.request_uri)
ngx.say("query_string: ", ngx.var.query_string)
ngx.say("scheme: ", ngx.var.scheme)
ngx.say("server_protocol: ", ngx.var.server_protocol)
ngx.say("server_addr: ", ngx.var.server_addr)
ngx.say("server_name: ", ngx.var.server_name)
ngx.say("server_port: ", ngx.var.server_port)
ngx.say("uri: ", ngx.var.uri)

if jit then
	ngx.say(jit.version)
else
	ngx.say(_VSERSION)
end

ngx.shared.shared_dict:flush_all()
--]]

--[[
local src_ip = ngx.var["X-Real-IP"] or ngx.var.remote_addr
util.send_warning("cdn告警", src_ip.." says hello, from openresty")


local args = ngx.req.get_uri_args()
local dest_path = args["dest_path"]

if not dest_path then
	ngx.log(ngx.ERR, "no dest path")
	return
end

--ngx.log(ngx.ERR, "start reading data")
ngx.req.read_body()
local tmp_body_file = ngx.req.get_body_file()
if not tmp_body_file then
	ngx.log(ngx.ERR, "no body file")
	ngx.exit(ngx.HTTP_ILLEGAL)
end

--ngx.log(ngx.ERR, "finish reading data")

local status, msg = util.file_copy(tmp_body_file, dest_path)
if status ~= 0 then
	ngx.log(ngx.ERR, "status: ", status, ", msg: ", msg)
end

--]]


--测试webhdfs
local args = ngx.req.get_uri_args()
local path = args["path"]
if not path then
	ngx.say("give me a path in hdfs, eg: url?path=/logs/20161122/auc.tangdou.com/big_2016112210_access.log")
	return
end

local ret = webhdfs.get_status(path)
ngx.say("httpStatus : ", ret.httpStatus)

for k,v in pairs(ret.FileStatus) do
	ngx.say(k, " : ", v)
end






