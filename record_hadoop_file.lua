local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"

local args = ngx.req.get_uri_args()
local domain_name = args["domain_name"]
local file_name = args["file_name"] 
local file_date = args["file_date"]
if not domain_name or not file_name or not file_date then
	ngx.log(ngx.ERR, "no domain_name or file_name, ", domain_name, ", ", file_name,
					", ", file_date)
	ngx.exit(ngx.HTTP_ILLEGAL)
end

local regex_expr = [=[^(small|big)_([0-9]{10})_access\.log$]=]
local m = ngx.re.match(file_name, regex_expr, "o")
if not m then
	ngx.log(ngx.ERR, "file_name not match regex: ", regex_expr, "file_name: ", file_name)
	ngx.exit(ngx.HTTP_ILLEGAL)	
end

local file_type = m[1]
local date_hour = m[2].."0000"

if file_type == "small" then
	file_type = 0
elseif file_type == "big" then
	file_type = 1
end

local hadoop_file_path = conf.hadoop_root..file_date.."/"..domain_name.."/"..file_name

local query_sql = string.format("insert into tb_hadoop_files"
								.." (domain_name, date_hour, file_type, hdfs_path)"
								.." values(%s, %s, %d, %s)"
								.." on duplicate key update append_times = append_times + 1",
								ngx.quote_sql_str(domain_name),
								ngx.quote_sql_str(date_hour),
								file_type,
								ngx.quote_sql_str(hadoop_file_path))
ngx.log(ngx.DEBUG, "query_sql: ", query_sql)

local db, err = mysql:new()
if not db then
	ngx.log(ngx.ERR, "failed to instantiate mysql: ", err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

db:set_timeout(1000) -- 1 sec

local ok, err, errcode, sqlstate = db:connect(conf.hadoop_db)
if not ok then
	ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
	ngx.say(err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local res, err, errcode, sqlstate = db:query(query_sql)
if not res then
	ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
	ngx.log(ngx.ERR, "query_sql: ", query_sql)
	ngx.say(err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local ok, err = db:set_keepalive(10000, 100)
if not ok then
	ngx.log(ngx.ERR, "failed to set keepalive: ", err)
	db:close()
end

--返回成功信息
ngx.say("record_success")
ngx.exit(ngx.HTTP_OK)




