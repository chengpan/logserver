local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"

local args = ngx.req.get_uri_args()
local file_name = args["file"]
ngx.log(ngx.DEBUG, "file_name: ", file_name)

if not file_name then
	ngx.log(ngx.ERR, "no file name")
	ngx.exit(ngx.HTTP_ILLEGAL)
end

local regex_expr = '.*/([^/]+)/([^/]+)$'
local m = ngx.re.match(file_name, regex_expr, "o")
if not m then
	ngx.log(ngx.ERR, "file_name not match regex: ", regex_expr)
	ngx.exit(ngx.HTTP_ILLEGAL)	
end

--ngx.log(ngx.DEBUG, "file_name: ", m[0], ", domain: ", m[1], ", file: ", m[2])

--提取日志domain, time
local log_domain    = m[1]
local log_file_name = m[2]

regex_expr = [==[^(ats|http_access).*([0-9]{10})\.log(\.1)?$]==]
m = ngx.re.match(log_file_name, regex_expr, "o")
if not m then
	ngx.log(ngx.ERR, "log_file_name not match regex: ", regex_expr)
	ngx.exit(ngx.HTTP_ILLEGAL)	
end

local log_file_hour = m[2]
local sql_datetime = util.mk_sql_datetime(log_file_hour)

local sql_str = string.format("select domain_name from tb_uploaded_domain_log_info where"
							.." domain_name = %s and date_hour = %s",
							ngx.quote_sql_str(log_domain),
							ngx.quote_sql_str(sql_datetime))
--ngx.log(ngx.DEBUG, "sql_str: ", sql_str)

local db, err = mysql:new()
if not db then
	ngx.log(ngx.ERR, "failed to instantiate mysql: ", err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local ok, err, errcode, sqlstate = db:connect(conf.domain_ip_db)

if not ok then
	ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local res, err, errcode, sqlstate = db:query(sql_str)
if not res then
	ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

if #res ~= 0 then
	ngx.say("found_in_db")
else
	ngx.say("not_found")
end

ngx.exit(ngx.HTTP_OK)
