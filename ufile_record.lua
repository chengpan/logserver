local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"

local args = ngx.req.get_uri_args()
local file_key = args["file_key"]
ngx.log(ngx.DEBUG, "file_key: ", file_key)

if not file_key then
	ngx.log(ngx.ERR, "no file key")
	ngx.exit(ngx.HTTP_ILLEGAL)
end

local regex_expr = '([^/]+)/([^/]+)$'
local m = ngx.re.match(file_key, regex_expr, "o")
if not m then
	ngx.log(ngx.ERR, "file_key not match regex: ", regex_expr)
	ngx.exit(ngx.HTTP_ILLEGAL)	
end

--提取日志domain, time
local log_domain    = m[1]
local log_file_name = m[2]

regex_expr = [==[^(ats|http_access).*([0-9]{10})\.log(\.1)?.*$]==]
m = ngx.re.match(log_file_name, regex_expr, "o")
if not m then
	ngx.log(ngx.ERR, "log_file_name not match regex: ", regex_expr)
	ngx.exit(ngx.HTTP_ILLEGAL)	
end

local log_file_hour = m[2].."0000"
local download_url = conf.ufile_url_prefix..file_key

--ngx.log(ngx.DEBUG, "file key log domain: ", log_domain)
--ngx.log(ngx.DEBUG, "file key log hour: ", log_file_hour)
--ngx.log(ngx.DEBUG, "file key log url: ", download_url)

local db, err = mysql:new()
if not db then
	ngx.log(ngx.ERR, "failed to instantiate mysql: ", err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

db:set_timeout(1000) -- 1 sec

local ok, err, errcode, sqlstate = db:connect(conf.domain_ip_db)
if not ok then
	ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local query_sql = string.format("insert into tb_uploaded_domain_log_info"
								.." (domain_name, date_hour, download_url)"
								.." values(%s, %s, %s)",
								ngx.quote_sql_str(log_domain),
								ngx.quote_sql_str(log_file_hour),
								ngx.quote_sql_str(download_url))

local res, err, errcode, sqlstate = db:query(query_sql)
if not res then
	ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
	ngx.log(ngx.ERR, "query_sql: ", query_sql)
	return
end

local ok, err = db:set_keepalive(10000, 100)
if not ok then
	ngx.log(ngx.ERR, "failed to set keepalive: ", err)
end

--返回成功信息
ngx.say("upload_success")
ngx.exit(ngx.HTTP_OK)
